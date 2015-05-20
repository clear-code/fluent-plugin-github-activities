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

    DEFAULT_HOST = "api.github.com"
    DEFAULT_PORT = 443
    DEFAULT_USE_SSL = true

    config_param :users, :string, :default => nil
    config_param :users_list, :string, :default => nil
    config_param :host, :string, :default => DEFAULT_HOST
    config_param :port, :integer, :default => DEFAULT_PORT
    config_param :use_ssl, :bool, :default => DEFAULT_USE_SSL

    def initialize
      super

      require "net/https"
      require "json"

      @request_queue = Queue.new

      prepare_users_list
      prepare_initial_queues
    end

    def start
      @crawler = Crawler.new(:host => @host,
                             :port => @port,
                             :use_ssl => @use_ssl,
                             :request_queue => @request_queue)
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
        @request_queue.push(user_activities(user))
      end
    end

    def user_activities(user)
      "/users/#{user}/events/public"
    end

    class Crawler
      def initialize(params)
        @host = params[:host]
        @port = params[:port]
        @use_ssl = params[:use_ssl]
        @request_queue = params[:request_queue]
      end

      def start
        process_request
      end

      def process_request
        path = @request_queue.shift
        custom_headers = {}
        request = Net::HTTP::Get.new(path, custom_headers)

        http = Net::HTTP.new(@host, @port)
        http.use_ssl = @use_ssl
        http.start do
          http.request(request) do |response|
            process_response(response)
          end
        end
      end

      def process_response(response)
        events = JSON.parse(response.body)
        # puts events
      end
    end
  end
end
