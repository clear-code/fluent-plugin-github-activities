# -*- coding: utf-8 -*-
#
# This file is part of fluent-plugin-github-activities.
#
# fluent-plugin-github-activities is free software: you can
# redistribute it and/or modify it under the terms of the GNU Lesser
# General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# fluent-plugin-github-activities is distributed in the hope that
# it will be useful, but WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE.  See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with fluent-plugin-github-activities.  If not, see
# <http://www.gnu.org/licenses/>.

require "uri"
require "net/https"
require "json"

module Fluent
  module GithubActivities
    class Crawler
      class EmptyRequestQueue < StandardError
      end

      attr_writer :on_emit
      attr_reader :request_queue

      def initialize(options={})
        @username = options[:username]
        @password = options[:password]
        @log = options[:logger]
        @request_queue = options[:request_queue] || []
      end

      def process_request
        raise EmptyRequestQueue.new if @request_queue.empty?

        request = @request_queue.shift
        $log.info("GithubActivities::Crawler: processing request: #{request.inspect}")
        if request[:process_after] and
             Time.now.to_i < request[:process_after]
          @request_queue.push(request)
          return false
        end

        uri = request_uri(request)
        extra_headers = extra_request_headers(request)
        response = nil

        $log.info("GithubActivities::Crawler: requesting to #{uri.inspect}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.is_a?(URI::HTTPS)
        http.start do |http|
          http_request = Net::HTTP::Get.new(uri.path, extra_headers)
          if @username and @password
            http_request.basic_auth(@username, @password)
          end
          response = http.request(http_request)
        end
        $log.info("GithubActivities::Crawler: response: #{response.inspect}")

        case response
        when Net::HTTPSuccess
          body = JSON.parse(response.body)
          $log.info("GithubActivities::Crawler: request type: #{request[:type]}")
          case request[:type]
          when TYPE_EVENTS
            events = body
            $log.info("GithubActivities::Crawler: events size: #{events.size}")
            process_user_events(request[:user], events)
            reserve_user_events(request[:user], :previous_response => response)
          when TYPE_COMMIT
            process_commit(body)
          end
        when Net::HTTPNotModified
          case request[:type]
          when TYPE_EVENTS
            reserve_user_events(request[:user],
                                :previous_response => response,
                                :previous_entity_tag => extra_headers["If-None-Match"])
          end
        end
        true
      end

      def request_uri(request)
        uri = nil
        case request[:type]
        when TYPE_EVENTS
          uri = user_activities(request[:user])
        else
          uri = request[:uri]
        end
        URI(uri)
      end

      def extra_request_headers(request)
        headers = {}
        if request[:previous_entity_tag]
          headers["If-None-Match"] = request[:previous_entity_tag]
        end
        headers
      end

      def reserve_user_events(user, options={})
        request = {
          :type => TYPE_EVENTS,
          :user => user,
        }
        response = options[:previous_response]
        if response
          now = options[:now] || Time.now
          interval = response["X-Poll-Interval"].to_i
          time_to_process = now.to_i + interval
          request[:previous_entity_tag] = response["ETag"] ||
                                            options[:previous_entity_tag]
          request[:process_after] = time_to_process
        end
        @request_queue.push(request)
      end

      def process_user_events(user, events)
        events.each do |event|
          process_user_event(user, event)
        end
      end

      def process_user_event(user, event)
        # see also: https://developer.github.com/v3/activity/events/types/
        case event["type"]
        when "PushEvent"
          process_push_event(event)
        when "CommitCommentEvent"
          emit("commit-comment", event)
        when "IssuesEvent"
          process_issue_event(event)
        when "IssueCommentEvent"
          emit("issue.comment", event)
        when "ForkEvent"
          emit("fork", event)
        when "PullRequestEvent"
          emit("pull-request", event)
        else
          emit(event["type"], event)
        end
      end

      def process_push_event(event)
        payload = event["payload"]
        payload["commits"].each do |commit|
          @request_queue.push(:type => TYPE_COMMIT,
                              :uri  => commit["url"])
        end
        emit("push", event)
      end

      def process_commit(commit)
        emit("commit", commit)
      end

      def process_issue_event(event)
        payload = event["payload"]
        case payload["action"]
        when "opened"
          emit("issue.open", event)
        when "closed"
          emit("issue.close", event)
        when "reopened"
          emit("issue.reopen", event)
        when "assigned"
          emit("issue.assign", event)
        when "unassigned"
          emit("issue.unassign", event)
        when "labeled"
          emit("issue.label", event)
        when "unlabeled"
          emit("issue.unlabel", event)
        end
      end

      private
      def user_activities(user)
        "https://api.github.com/users/#{user}/events/public"
      end

      def emit(tag, record)
        $log.trace("GithubActivities::Crawler: emit => #{tag}, #{record.inspect}")
        @on_emit.call(tag, record) if @on_emit
      end
    end
  end
end
