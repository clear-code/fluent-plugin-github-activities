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

require "fluent/plugin/filter"

module Fluent
  module Plugin
    class GithubActivitiesFilter < Fluent::Plugin::Filter
      Fluent::Plugin.register_filter("github-activities", self)

      def configure(conf)
        super
      end

      def filter(tag, time, record)
        new_record = {}
        case record["type"]
        when "PushEvent"
        when "CommitCommentEvent"
        when "IssuesEvent"
          new_record["subject"] = record.dig("repo", "name")
          new_record["message"] = "#{record.dig('actor', 'display_login')} " \
                                  "#{record.dig('payload', 'action')} " \
                                  "[#{record.dig('repo', 'name')}##{record.dig('payload', 'issue', 'number')}](#{record.dig('payload', 'issue', 'html_url')})\n" \
                                  "#{record.dig('payload', 'issue', 'title')}\n#{record.dig('payload', 'issue', 'body')}"
        when "IssueCommentEvent"
          new_record["subject"] = record.dig("repo", "name")
          new_record["message"] = "#{record.dig('actor', 'display_login')} " \
                                  "#{record.dig('payload', 'action')} " \
                                  "[#{record.dig('repo', 'name')}##{record.dig('payload', 'issue', 'number')}-#{record.dig('payload', 'comment', 'id')}](#{record.dig('payload', 'comment', 'html_url')})\n" \
                                  "#{record.dig('payload', 'issue', 'title')}\n#{record.dig('payload', 'comment', 'body')}"
        when "ForkEvent"
        when "PullRequestEvent"
        when "CreateEvent"
        else
          new_record = record
        end
        new_record
      end
    end
  end
end
