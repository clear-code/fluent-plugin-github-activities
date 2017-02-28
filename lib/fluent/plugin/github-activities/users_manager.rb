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

require "json"

module Fluent
  module Plugin
    module GithubActivities
      class UsersManager
        DEFAULT_LAST_EVENT_TIMESTAMP = -1

        def initialize(params={})
          @users = params[:users]
          @pos_storage = params[:pos_storage]
        end

        def generate_initial_requests
          @users.collect do |user|
            new_events_request(user)
          end
        end

        def new_events_request(user, options={})
          request = {
            type: TYPE_EVENTS,
            user: user,
          }
          response = options[:previous_response]
          if response
            now = options[:now] || Time.now
            interval = response["X-Poll-Interval"].to_i
            time_to_process = now.to_i + interval
            request[:previous_entity_tag] = response["ETag"] ||
                                            options[:previous_entity_tag]
            request[:process_after] = time_to_process
          else
            request[:previous_entity_tag] = options[:previous_entity_tag] if options.key?(:previous_entity_tag)
          end
          request
        end

        def position_for(user)
          @pos_storage.get(user)
        end

        def save_position_for(user, params)
          user = @pos_storage.get(user) || {}

          if params[:entity_tag]
            user["entity_tag"] = params[:entity_tag]
          end

          if params[:last_event_timestamp] and
            params[:last_event_timestamp] != DEFAULT_LAST_EVENT_TIMESTAMP
            old_timestamp = user["last_event_timestamp"]
            if old_timestamp.nil? or old_timestamp < params[:last_event_timestamp]
              user["last_event_timestamp"] = params[:last_event_timestamp]
            end
          end

          @pos_storage.save
        end
      end
    end
  end
end
