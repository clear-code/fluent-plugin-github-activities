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
    DEFAULT_BASE_TAG = "github-activity"
    DEFAULT_CLIENTS = 4

    Plugin.register_input("github-activities", self)

    config_param :access_token, :string, :default => nil
    config_param :users, :string, :default => nil
    config_param :users_list, :string, :default => nil
    config_param :include_commits_from_pull_request, :bool, :default => false
    config_param :include_foreign_commits, :bool, :default => false
    config_param :base_tag, :string, :default => DEFAULT_BASE_TAG
    config_param :pos_file, :string, :default => nil
    config_param :clients, :integer, :default => DEFAULT_CLIENTS
    config_param :interval, :integer, :default => 1

    def initialize
      super

      require "thread"
      require "pathname"
      require "fluent/plugin/github-activities"
    end

    def start
      @base_tag = @base_tag.sub(/\.\z/, "")

      users = prepare_users_list
      n_clients = [@clients, users.size].min
      @interval = @interval * n_clients

      @client_threads = []
      @request_queue = Queue.new

      users_manager_params = {
        :users    => users,
        :pos_file => @pos_file,
      }
      users_manager = ::Fluent::GithubActivities::UsersManager.new(users_manager_params)
      users_manager.generate_initial_requests.each do |request|
        @request_queue.push(request)
      end

      n_clients.times do
        @client_threads << Thread.new do
          crawler_options = {
            :access_token => @access_token,
            :watching_users => users,
            :include_commits_from_pull_request => @include_commits_from_pull_request,
            :include_foreign_commits => @include_foreign_commits,
            :pos_file => @pos_file,
            :request_queue => @request_queue,
            :default_interval => @interval,
          }
          crawler = ::Fluent::GithubActivities::Crawler.new(crawler_options)
          crawler.on_emit = lambda do |tag, record|
            Engine.emit("#{@base_tag}.#{tag}", Engine.now, record)
          end

          loop do
            crawler.process_request
            sleep(crawler.interval_for_next_request)
          end
        end
      end
    end

    def shutdown
      @client_threads.each(&:exit)
    end

    private
    def prepare_users_list
      @users ||= ""
      users = @users.split(",")

      if @users_list
        users_list = Pathname(@users_list)
        if users_list.exist?
          list = users_list.read
          users += list.split("\n")
        end
      end

      users = users.collect do |user|
        user.strip
      end.reject do |user|
        user.empty?
      end

      users
    end
  end
end
