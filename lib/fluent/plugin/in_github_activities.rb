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

    GITHUB_API_BASE = "https://api.github.com"

    config_param :users, :string, :default => nil
    config_param :users_list, :string, :default => nil

    def initialize
      super

      @client = create_client
      @request_queue = Queue.new

      prepare_users_list
      prepare_initial_queues
    end

    def start
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
      "#{GITHUB_API_BASE}/users/#{user}/events/public"
    end
  end
end
