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
require "time"

module Fluent
  module GithubActivities
    class Crawler
      class EmptyRequestQueue < StandardError
      end

      NO_INTERVAL = 0
      DEFAULT_INTERVAL = 1

      DEFAULT_LAST_EVENT_TIMESTAMP = -1

      RELATED_USER_IMAGE_KEY = "$github-activities-related-avatar"
      RELATED_ORGANIZATION_IMAGE_KEY = "$github-activities-related-organization-logo"
      RELATED_EVENT = "$github-activities-related-event"

      attr_writer :on_emit
      attr_reader :request_queue, :interval_for_next_request

      def initialize(options={})
        @access_token = options[:access_token]

        @watching_users = options[:watching_users] || []
        @users_manager = options[:users_manager]

        @include_commits_from_pull_request = options[:include_commits_from_pull_request]
        @include_foreign_commits = options[:include_foreign_commits]

        @request_queue = options[:request_queue] || []

        @default_interval = options[:default_interval] || DEFAULT_INTERVAL
      end

      def process_request
        raise EmptyRequestQueue.new if @request_queue.empty?

        request = @request_queue.shift
        $log.debug("GithubActivities::Crawler: processing request: #{request.inspect}") if $log
        if request[:process_after] and
             Time.now.to_i < request[:process_after]
          @request_queue.push(request)
          @interval_for_next_request = NO_INTERVAL
          return false
        end

        uri = request_uri(request)
        extra_headers = extra_request_headers(request)

        $log.debug("GithubActivities::Crawler: requesting to #{uri.inspect}") if $log
        response = http_get(uri, extra_headers)
        $log.debug("GithubActivities::Crawler: response: #{response.inspect}") if $log

        case response
        when Net::HTTPSuccess
          body = JSON.parse(response.body)
          $log.trace("GithubActivities::Crawler: request type: #{request[:type]}") if $log
          case request[:type]
          when TYPE_EVENTS
            events = body
            $log.trace("GithubActivities::Crawler: events size: #{events.size}") if $log
            process_user_events(request[:user], events)
            reserve_user_events(request[:user], :previous_response => response)
            @users_manager.save_position_for(request[:user], :entity_tag => response["ETag"])
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
          @interval_for_next_request = NO_INTERVAL
          return true
        when Net::HTTPNotFound
          case request[:type]
          when TYPE_COMMIT
            fake_body = {
              "sha"    => request[:sha],
              "author" => {},
            }
            process_commit(fake_body, request[:push])
          end
        end
        @interval_for_next_request = @default_interval
        return true
      end

      def request_uri(request)
        uri = nil
        case request[:type]
        when TYPE_EVENTS
          uri = user_activities(request[:user])
        else
          uri = request[:uri]
        end
      end

      def extra_request_headers(request)
        headers = {}
        if request[:previous_entity_tag]
          headers["If-None-Match"] = request[:previous_entity_tag]
        elsif request[:type] == TYPE_EVENTS
          position = @users_manager.position_for(request[:user])
          if position
          entity_tag = position["entity_tag"]
          headers["If-None-Match"] = entity_tag if entity_tag
          end
        end
        headers
      end

      def reserve_user_events(user, options={})
        request = @users_manager.new_events_request(user, options)
        @request_queue.push(request)
      end

      def process_user_events(user, events)
        last_event_timestamp = DEFAULT_LAST_EVENT_TIMESTAMP
        position = @users_manager.position_for(user)
        if position and position["last_event_timestamp"]
          last_event_timestamp = position["last_event_timestamp"]
        end

        events = events.sort do |a, b|
          b["created_at"] <=> a["created_at"]
        end
        events.each do |event|
          timestamp = Time.parse(event["created_at"]).to_i
          next if timestamp <= last_event_timestamp
          process_user_event(user, event)
          @users_manager.save_position_for(user, :last_event_timestamp => timestamp)
        end
      end

      def process_user_event(user, event)
        # see also: https://developer.github.com/v3/activity/events/types/
        event[RELATED_USER_IMAGE_KEY] = event["actor"]["avatar_url"]
        if event["org"]
          event[RELATED_ORGANIZATION_IMAGE_KEY] = event["org"]["avatar_url"]
        end
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
      rescue StandardError => error
        $log.exception(error)
      end

      def process_push_event(event)
        payload = event["payload"]
        commit_refs = payload["commits"]
        if !@include_commits_from_pull_request and
             push_event_from_merged_pull_request?(event)
          return
        end
        commit_refs.reverse.each do |commit_ref|
          @request_queue.push(:type => TYPE_COMMIT,
                              :uri  => commit_ref["url"],
                              :sha  => commit_ref["sha"],
                              :push => event)
        end
        # emit("push", event)
      end

      def process_commit(commit, push_event)
        $log.debug("GithubActivities::Crawler: processing commit #{commit["sha"]}") if $log
        user = commit["author"]["login"]

        if user and (@include_foreign_commits or watching_user?(user))
          commit[RELATED_USER_IMAGE_KEY] = push_event["actor"]["avatar_url"]
          if push_event["org"]
            commit[RELATED_ORGANIZATION_IMAGE_KEY] = push_event["org"]["avatar_url"]
          end
          commit[RELATED_EVENT] = push_event
          emit("commit", commit)
        end

        commit_refs = push_event["payload"]["commits"]
        target_commit_ref = commit_refs.find do |commit_ref|
          commit_ref["sha"] == commit["sha"]
        end
        target_commit_ref["commit"] = commit if target_commit_ref

        completely_fetched = commit_refs.all? do |commit_ref|
          commit_ref["commit"]
        end
        emit("push", push_event) if completely_fetched
      end

      def watching_user?(user)
        @watching_users.include?(user)
      end

      def process_issue_event(event)
        payload = event["payload"]
        case payload["action"]
        when "opened"
          emit("issue-open", event)
        when "closed"
          emit("issue-close", event)
        when "reopened"
          emit("issue-reopen", event)
        when "assigned"
          emit("issue-assign", event)
        when "unassigned"
          emit("issue-unassign", event)
        when "labeled"
          emit("issue-label", event)
        when "unlabeled"
          emit("issue-unlabel", event)
        end
      end

      def process_pull_request_event(event)
        payload = event["payload"]
        case payload["action"]
        when "opened"
          emit("pull-request", event)
        when "closed"
          if payload["pull_request"]["merged"]
            emit("pull-request-merged", event)
          else
            emit("pull-request-cancelled", event)
          end
        when "reopened"
          emit("pull-request-reopen", event)
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
          emit("pull-request-comment", event)
          # emit("pull-request.cancel", event)
        else
          emit("issue-comment", event)
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

      def user_info(user)
        "https://api.github.com/users/#{user}"
      end

      def emit(tag, record)
        $log.trace("GithubActivities::Crawler: emit => #{tag}, #{record.inspect}") if $log
        @on_emit.call(tag, record) if @on_emit
      end

      def http_get(uri, extra_headers={})
        parsed_uri = URI(uri)
        if @access_token
          extra_headers["Authorization"] = "token #{@access_token}"
        end
        response = nil
        http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
        http.use_ssl = parsed_uri.is_a?(URI::HTTPS)
        http.start do |http|
          http_request = Net::HTTP::Get.new(parsed_uri.path, extra_headers)
          response = http.request(http_request)
        end
        response
      end
    end
  end
end
