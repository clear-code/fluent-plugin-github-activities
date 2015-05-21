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
      attr_writer :on_emit

      def initialize(params)
        @request_queue = params[:request_queue]
      end

      def process_request
        request = @request_queue.shift

        uri = request_uri(request)
        response = Net::HTTP.get_response(uri)

        case response
        when Net::HTTPSuccess
          body = JSON.parse(response.body)
          case request[:type]
          when TYPE_EVENTS
            events = body
            process_user_events(request[:user], events)
          when TYPE_COMMIT
            process_commit(body)
          end
        end
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

      def user_activities(user)
        "https://api.github.com/users/#{user}/events/public"
      end

      def process_user_events(user, events)
        events.each do |event|
          process_user_event(user, event)
        end
        @request_queue.push(:type => TYPE_EVENTS,
                            :user => user)
      end

      def process_user_event(user, event)
        # see also: https://developer.github.com/v3/activity/events/types/
        case event["type"]
        when "PushEvent"
          process_push_event(event)
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

      private
      def emit(tag, record)
        @on_emit.call(tag, record) if @on_emit
      end
    end
  end
end
