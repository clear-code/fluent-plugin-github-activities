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

require "thread"
require "pathname"
require "fluent/plugin/input"
require "fluent/plugin/github-activities"

module Fluent
  module Plugin
    class GithubActivitiesInput < Fluent::Plugin::Input
      DEFAULT_BASE_TAG = "github-activity"
      DEFAULT_CLIENTS = 4

      helpers :thread, :storage

      Fluent::Plugin.register_input("github-activities", self)

      config_param :access_token, :string, default: nil, secret: true
      config_param :users, :array, default: []
      config_param :users_list, :string, default: nil
      config_param :include_commits_from_pull_request, :bool, default: false
      config_param :include_foreign_commits, :bool, default: false
      config_param :base_tag, :string, default: DEFAULT_BASE_TAG
      config_param :pos_file, :string, default: nil, deprecated: "Use storage instead."
      config_param :clients, :integer, default: DEFAULT_CLIENTS
      config_param :interval, :integer, default: 1

      config_section :storage do
        config_set_default :usage, "in-github-activities"
        config_set_default :@type, Fluent::Plugin::Storage::DEFAULT_TYPE
        config_set_default :persistent, false
      end

      def configure(conf)
        super

        @base_tag = @base_tag.sub(/\.\z/, "")
        @users += load_users_list
        @n_clients = [@clients, @users.size].min
        @interval = @interval * @n_clients
        raise Fluent::ConfigError, "You can define <storage> section at once" unless @storage_configs.size == 1
        storage_section = @storage_configs.first
        storage_config = storage_section.corresponding_config_element
        @pos_storage = storage_create(usage: storage_section.usage,
                                      conf: storage_config,
                                      default_type: Fluent::Plugin::Storage::DEFAULT_TYPE)
      end

      def start
        super

        @request_queue = Queue.new

        users_manager_params = {
          users: @users,
          pos_storage: @pos_storage,
        }
        users_manager = ::Fluent::Plugin::GithubActivities::UsersManager.new(users_manager_params)
        users_manager.generate_initial_requests.each do |request|
          @request_queue.push(request)
        end
        @n_clients.times do |n|
          thread_create("in_github_activity_#{n}".to_sym) do
            crawler_options = {
              access_token: @access_token,
              watching_users: @users,
              include_commits_from_pull_request: @include_commits_from_pull_request,
              include_foreign_commits: @include_foreign_commits,
              pos_storage: @pos_storage,
              request_queue: @request_queue,
              default_interval: @interval,
              log: log
            }
            crawler = ::Fluent::Plugin::GithubActivities::Crawler.new(crawler_options)
            crawler.on_emit = lambda do |tag, record|
              router.emit("#{@base_tag}.#{tag}", Engine.now, record)
            end

            loop do
              crawler.process_request
              sleep(crawler.interval_for_next_request)
            end
          end
        end
      end

      private

      def load_users_list
        users = []
        if @users_list
          users_list = Pathname(@users_list)
          if users_list.exist?
            list = users_list.read
            users += list.split("\n")
          end
        end

        users.collect(&:strip).reject(&:empty?)
      end
    end
  end
end
