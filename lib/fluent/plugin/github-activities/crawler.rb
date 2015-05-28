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
require "pathname"

require "fluent/plugin/github-activities/safe_file_writer"

module Fluent
  module GithubActivities
    class Crawler
      class EmptyRequestQueue < StandardError
      end

      DEFAULT_LAST_EVENT_TIMESTAMP = -1

      attr_writer :on_emit
      attr_reader :request_queue

      def initialize(options={})
        @username = options[:username]
        @password = options[:password]

        @include_commits_from_pull_request = options[:include_commits_from_pull_request]
        @include_foreign_commits = options[:include_foreign_commits]

        @positions = {}
        @pos_file = options[:pos_file]
        @pos_file = Pathname(@pos_file) if @pos_file
        load_positions

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
            save_user_position(request[:user], :entity_tag => response["ETag"])
          when TYPE_COMMIT
            process_commit(body, request[:push])
          end
        when Net::HTTPNotModified
          case request[:type]
          when TYPE_EVENTS
            reserve_user_events(request[:user],
                                :previous_response => response,
                                :previous_entity_tag => extra_headers["If-None-Match"])
          end
          return false
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
        elsif request[:type] == TYPE_EVENTS and @positions[request[:user]]
          entity_tag = @positions[request[:user]]["entity_tag"]
          headers["If-None-Match"] = entity_tag if entity_tag
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
        last_event_timestamp = DEFAULT_LAST_EVENT_TIMESTAMP
        if @positions[user] and @positions[user]["last_event_timestamp"]
          last_event_timestamp = @positions[user]["last_event_timestamp"]
        end
        events.each do |event|
          timestamp = Time.parse(event["created_at"]).to_i
          next if timestamp <= last_event_timestamp
          process_user_event(user, event)
          save_user_position(user, :last_event_timestamp => timestamp)
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
          process_issue_or_pull_request_comment_event(event)
        when "ForkEvent"
          emit("fork", event)
        when "PullRequestEvent"
          process_pull_request_event(event)
        when "CreateEvent"
          process_create_event(event)
        else
          emit(event["type"], event)
        end
      end

      def process_push_event(event)
        payload = event["payload"]
        commit_refs = payload["commits"]
        if !@include_commits_from_pull_request and
             push_event_from_merged_pull_request?(event)
          return
        end
        commit_refs.reverse.each do |commit_ref|
          @request_queue.unshift(:type => TYPE_COMMIT,
                                 :uri  => commit_ref["url"],
                                 :push => event)
        end
        # emit("push", event)
      end

      def process_commit(commit, push_event)
        emit("commit", commit)

        commit_refs = push_event["payload"]["commits"]
        target_commit_ref = commit_refs.find do |commit_ref|
          commit_ref["url"] == commit["url"]
        end
        target_commit_ref["commit"] = commit if target_commit_ref

        completely_fetched = commit_refs.all? do |commit_ref|
          commit_ref["commit"]
        end
        emit("push", push_event) if completely_fetched
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

      def process_pull_request_event(event)
        payload = event["payload"]
        case payload["action"]
        when "opened"
          emit("pull-request.open", event)
        when "closed"
          if payload["pull_request"]["merged"]
            emit("pull-request.merged", event)
          else
            emit("pull-request.cancelled", event)
          end
        when "reopened"
          emit("pull-request.reopen", event)
        end
      end

      MERGE_COMMIT_MESSAGE_PATTERN = /\AMerge pull request #\d+ from [^\/]+\/[^\/]+\n\n/

      def push_event_from_merged_pull_request?(event)
        payload = event["payload"]
        inserted_requests = []
        commit_refs = payload["commits"]
        if MERGE_COMMIT_MESSAGE_PATTERN =~ commit_refs.last["message"]
          true
        else
          false
        end
      end

      def process_issue_or_pull_request_comment_event(event)
        payload = event["payload"]
        if payload["issue"]["pull_request"]
          emit("pull-request.comment", event)
          # emit("pull-request.cancel", event)
        else
          emit("issue.comment", event)
        end
      end

      def process_create_event(event)
        payload = event["payload"]
        case payload["ref_type"]
        when "branch"
          emit("branch", event)
        when "tag"
          emit("tag", event)
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

      def load_positions
        return unless @pos_file
        return unless @pos_file.exist?

        @positions = JSON.parse(@pos_file.read)
      rescue
        @positions = {}
      end

      def save_positions
        return unless @pos_file
        SafeFileWriter.write(@pos_file, JSON.pretty_generate(@positions))
      end

      def save_user_position(user, params)
        @positions[user] ||= {}

        if params[:entity_tag]
          @positions[user]["entity_tag"] = params[:entity_tag]
        end

        if params[:last_event_timestamp] and
             params[:last_event_timestamp] != DEFAULT_LAST_EVENT_TIMESTAMP
          old_timestamp = @positions[user]["last_event_timestamp"]
          if old_timestamp.nil? or old_timestamp < params[:last_event_timestamp]
            @positions[user]["last_event_timestamp"] = params[:last_event_timestamp]
          end
        end

        save_positions
      end
    end
  end
end
