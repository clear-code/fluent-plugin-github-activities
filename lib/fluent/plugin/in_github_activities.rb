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

    Plugin.register_input("github-activities", self)

    config_param :users, :string, :default => nil
    config_param :users_list, :string, :default => nil
    config_param :base_tag, :string, :default => DEFAULT_BASE_TAG
    config_param :interval, :integer, :default => 1

    def initialize
      super

      require "thread"
      require "pathname"
      require "fluent/plugin/github-activities"
    end

    def start
      @thread = Thread.new do
        @crawler = ::Fluent::GithubActivities::Crawler.new
        @crawler.on_emit = lambda do |tag, record|
          Engine.emit("#{@base_tag}.#{tag}", Engine.now, record)
        end

        users = prepare_users_list
        users.each do |user|
          @crawler.reserve_user_events(user)
        end

        loop do
          @crawler.process_request
          sleep(@interval)
        end
      end
    end

    def shutdown
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
