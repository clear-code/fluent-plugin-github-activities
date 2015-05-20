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

module Fluent
  class GithubActivitiesInput < Input
    Plugin.register_input("github-activities", self)

    BASE_TAG = "github-activity"

    TYPE_EVENTS = :events
    TYPE_COMMIT = :commit

    config_param :users, :string, :default => nil
    config_param :users_list, :string, :default => nil

    def initialize
      super

      require "uri"
      require "net/https"
      require "json"

      @request_queue = Queue.new

      prepare_users_list
      prepare_initial_queues
    end

    def start
      @crawler = Crawler.new(:request_queue => @request_queue)
      @crawler.start
    end

    def shutdown
    end

    private
    def prepare_users_list
      @users ||= ""
      @users = @users.split(",")

      if @users_list
        users_list = Pathname(@users_list)
        if users_list.exist?
          list = users_list.read
          @users += list.split("\n")
        end
      end

      @users = @users.collect do |user|
        user.strip
      end.reject do |user|
        user.empty?
      end
    end

    def prepare_initial_queues
      @users.each do |user|
        @request_queue.push(:type => TYPE_EVENTS,
                            :url  => user_activities(user))
      end
    end

    def user_activities(user)
      "https://api.github.com/users/#{user}/events/public"
    end

    class Crawler
      def initialize(params)
        @request_queue = params[:request_queue]
      end

      def start
        process_request
      end

      def process_request
        request = @request_queue.shift

        request_type = request[:type]
        request_url = URI(request[:url])

        response = Net::HTTP.get_response(request_url)

        case response
        when Net::HTTPSuccess
          case request_type
          when TYPE_EVENTS
            events = JSON.parse(response.body)
            events.each do |event|
              process_event(event)
            end
          when TYPE_COMMIT
            commit = JSON.parse(response.body)
            process_commit(commit)
          end
        end
      end

      def process_event(event)
        # see also: https://developer.github.com/v3/activity/events/types/
        case event["type"]
        when "PushEvent"
          process_push_event(event)
        end
      end

      def process_push_event(event)
        payload = event["payload"]
        payload["commits"].each do |commit|
          @request_queue.push(:type => TYPE_COMMIT,
                              :url  => commit["url"])
        end
        Engine.emit("#{BASE_TAG}.push", Engine.now, event)
      end

      def process_commit(commit)
        Engine.emit("#{BASE_TAG}.commit", Engine.now, commit)
      end
    end
  end
end
