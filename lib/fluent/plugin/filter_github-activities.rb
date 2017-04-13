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

      AVAILABLE_EVENT_TYPES = [
        :commit_comment_event,
        :issues_event,
        :issue_comment_event,
        :fork_event,
        :pull_request_event,
        :create_event
      ]
      PLACEHOLDER_KEYS = {
        commit_comment_event: %w(repo_name login comment_url comment_body),
        issues_event: %w(repo_name login action number title body url),
        issue_comment_event: %w(repo_name login action number title body url comment_body comment_url),
        fork_event: %w(repo_name login forkee_repo_name forkee_url),
        pull_request_event: %w(repo_name login action number url title body),
        create_event: %w()
      }

      MESSAGE_PRESET_FORMAT = {}

      config_param :subject_key_name, :string, default: "subject"
      config_param :message_key_name, :string, default: "message"
      config_param :subject_preset_format, :enum, list: [:simple, :simple_markdown, :custom], default: :simple
      config_param :message_preset_format, :enum, list: [:simple, :simple_markdown, :details, :details_markdown, :custom], default: :simple
      config_section :subject_format, multiple: true do
        config_param :event_type, :enum, list: AVAILABLE_EVENT_TYPES
        config_param :format, :string
      end
      config_section :message_format, multiple: true do
        config_param :event_type, :enum, list: AVAILABLE_EVENT_TYPES
        config_param :format, :string
      end

      def configure(conf)
        super
      end

      def filter(tag, time, record)
        new_record = {}
        case event_type_to_symbol(record["type"])
        when :commit_comment_event
        when :issues_event
          new_record["subject"] = record.dig("repo", "name")
          new_record["message"] = "#{record.dig('actor', 'display_login')} " \
                                  "#{record.dig('payload', 'action')} " \
                                  "[#{record.dig('repo', 'name')}##{record.dig('payload', 'issue', 'number')}](#{record.dig('payload', 'issue', 'html_url')})\n" \
                                  "#{record.dig('payload', 'issue', 'title')}\n#{record.dig('payload', 'issue', 'body')}"
        when :issue_comment_event
          new_record["subject"] = record.dig("repo", "name")
          new_record["message"] = "#{record.dig('actor', 'display_login')} " \
                                  "#{record.dig('payload', 'action')} " \
                                  "[#{record.dig('repo', 'name')}##{record.dig('payload', 'issue', 'number')}-#{record.dig('payload', 'comment', 'id')}](#{record.dig('payload', 'comment', 'html_url')})\n" \
                                  "#{record.dig('payload', 'issue', 'title')}\n#{record.dig('payload', 'comment', 'body')}"
        when :fork_event
        when :pull_request_event
        when :create_event
        else
          new_record = record
        end
        new_record
      end

      private

      def event_type_to_symbol(event_type)
        event_type.split(/(?=[[:upper:]])/).map(&:downcase).join("_").to_sym
      end

      def preset_format(event_type)
        __send__("preset_format_#{@message_preset_format}_#{event_type}")
      end

      def preset_format_simple_commit_comment_event
      end
      def preset_format_simple_issues_event
      end
      def preset_format_simple_issue_comment_event
      end
      def preset_format_simple_fork_event
      end
      def preset_format_simple_pull_request_event
      end
      def preset_format_simple_create_event
      end
      def preset_format_simple_markdown_commit_comment_event
      end
      def preset_format_simple_markdown_issues_event
      end
      def preset_format_simple_markdown_issue_comment_event
      end
      def preset_format_simple_markdown_fork_event
      end
      def preset_format_simple_markdown_pull_request_event
      end
      def preset_format_simple_markdown_create_event
      end
      def preset_format_details_commit_comment_event
      end
      def preset_format_details_issues_event
      end
      def preset_format_details_issue_comment_event
      end
      def preset_format_details_fork_event
      end
      def preset_format_details_pull_request_event
      end
      def preset_format_details_create_event
      end
      def preset_format_detauls_markdown_commit_comment_event
      end
      def preset_format_detauls_markdown_issues_event
      end
      def preset_format_detauls_markdown_issue_comment_event
      end
      def preset_format_detauls_markdown_fork_event
      end
      def preset_format_detauls_markdown_pull_request_event
      end
      def preset_format_detauls_markdown_create_event
      end
    end
  end
end
