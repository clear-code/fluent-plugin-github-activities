# -*- mode: ruby; coding: utf-8 -*-
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

require "fluent/plugin/github-activities"

class CrawlerTest < Test::Unit::TestCase
  def setup
    @emitted_records = []

    @crawler = ::Fluent::GithubActivities::Crawler.new(crawler_options)
    @crawler.on_emit = lambda do |tag, record|
      @emitted_records << { :tag    => tag,
                            :record => record }
    end
    @crawler.request_queue.clear
  end

  def crawler_options
    {
      :include_commits_from_pull_request => false,
      :include_foreign_commits => false,
      :watching_users => [
        'piroor',
      ],
    }
  end

  def fill_extra_fields(event, parent_event=nil)
    if parent_event && parent_event["type"] == "PushEvent"
      push_event = fill_extra_fields(parent_event)
      event = event.merge(
        "$github-activities-related-event" => push_event
      )
    end

    parent_event ||= event

    event = event.merge(
      "$github-activities-related-avatar" => parent_event["actor"]["avatar_url"],
    )

    if parent_event["org"]
      event = event.merge(
        "$github-activities-related-organization-logo" => parent_event["org"]["avatar_url"],
      )
    end

    event
  end

  REQUEST_PATTERNS = {
    :user_events => {
      :request => { :type => :events,
                    :user => "username" },
      :uri     => "https://api.github.com/users/username/events/public",
      :headers => {},
    },
    :user_events_with_previous_request => {
      :request => { :type => :events,
                    :user => "username",
                    :previous_entity_tag => "aaaaa",
                    :process_after => 29 },
      :uri     => "https://api.github.com/users/username/events/public",
      :headers => {
        "If-None-Match" => "aaaaa",
      },
    },
  }

  data(REQUEST_PATTERNS)
  def test_request_uri(data)
    uri = @crawler.request_uri(data[:request])
    assert_equal(data[:uri], uri)
  end

  data(REQUEST_PATTERNS)
  def extra_request_headers(data)
    headers = @crawler.extra_request_headers(data[:request])
    assert_equal(data[:headers], headers)
  end

  class ReserveUserEventsTest < self
    def test_without_previous_response
      now = Time.now
      @crawler.reserve_user_events("username",
                                   :now => now)
      expected_request = {
        :type => :events,
        :user => "username",
      }
      assert_equal([expected_request],
                   @crawler.request_queue)
    end

    def test_with_previous_response
      now = Time.now
      @crawler.reserve_user_events("username",
                                   :now => now,
                                   :previous_response => {
                                     "ETag" => "aaaaa",
                                     "X-Poll-Interval" => 60,
                                   })
      expected_request = {
        :type => :events,
        :user => "username",
        :previous_entity_tag => "aaaaa",
        :process_after => now.to_i + 60,
      }
      assert_equal([expected_request],
                   @crawler.request_queue)
    end
  end

  class UserEventTest < self
    def test_generic
      event = {
        "type" => "test",
        "actor" => {},
        "created_at" => "2015-05-21T05:37:34Z",
      }
      @crawler.process_user_event("username", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "test",
            :record => fill_extra_fields(event) },
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class UserEventsTest < self
    def test_generic
      event = {
        "type" => "test",
        "actor" => {},
        "created_at" => "2015-05-21T05:37:34Z",
      }
      @crawler.process_user_events("username", [event])
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "test",
            :record => fill_extra_fields(event) },
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class PushEventTest < self
    def test_single_commit
      push = JSON.parse(fixture_data("push-event.json"))
      push = fill_extra_fields(push)
      base = "https://api.github.com/repos/clear-code/fluent-plugin-github-activities/commits"
      @crawler.process_user_event("user", push)

      expected_commit = JSON.parse(fixture_data("commit.json"))
      expected_push = JSON.parse(fixture_data("push-event.json"))

      expected_commit = fill_extra_fields(expected_commit, expected_push)

      expected_push = fill_extra_fields(expected_push)
      expected = {
        :request_queue => [
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/8e90721ff5d89f52b5b3adf0b86db01f03dc5588",
            :sha  => "8e90721ff5d89f52b5b3adf0b86db01f03dc5588",
            :push => expected_push },
        ],
        :emitted_records => [
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end

    def test_multiple_commits
      push = JSON.parse(fixture_data("push-event-multiple-commits.json"))
      push = fill_extra_fields(push)
      base = "https://api.github.com/repos/clear-code/fluent-plugin-github-activities/commits"
      @crawler.process_user_event("user", push)

      expected_commit = JSON.parse(fixture_data("commit.json"))
      expected_push = JSON.parse(fixture_data("push-event-multiple-commits.json"))

      expected_commit = fill_extra_fields(expected_commit, expected_push)

      expected_push = fill_extra_fields(expected_push)
      expected = {
        :request_queue => [
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/8e90721ff5d89f52b5b3adf0b86db01f03dc5588",
            :sha  => "8e90721ff5d89f52b5b3adf0b86db01f03dc5588",
            :push => expected_push },
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/63e085b7607a3043cfbf9a866561807fbdda8a10",
            :sha  => "63e085b7607a3043cfbf9a866561807fbdda8a10",
            :push => expected_push },
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/c85e33bace040b7b42983e14d2b11a491d102072",
            :sha  => "c85e33bace040b7b42983e14d2b11a491d102072",
            :push => expected_push },
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/8ce6de7582376187e17e233dbae13575311a8c0b",
            :sha  => "8ce6de7582376187e17e233dbae13575311a8c0b",
            :push => expected_push },
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/c908f319c7b6d5c5a69c8b675bde40dd990ee364",
            :sha  => "c908f319c7b6d5c5a69c8b675bde40dd990ee364",
            :push => expected_push },
        ].reverse,
        :emitted_records => [
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class IssuesEventTest < self
    def test_issue_open
      event = JSON.parse(fixture_data("issues-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "issue-open",
            :record => fill_extra_fields(event) }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class IssueCommentEventTest < self
    def test_issue_comment
      event = JSON.parse(fixture_data("issue-comment-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "issue-comment",
            :record => fill_extra_fields(event) }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class CommitCommentEventTest < self
    def test_multiple_commits
      event = JSON.parse(fixture_data("commit-comment-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "commit-comment",
            :record => fill_extra_fields(event) }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class ForkEventTest < self
    def test_multiple_commits
      event = JSON.parse(fixture_data("fork-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "fork",
            :record => fill_extra_fields(event) }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class PullRequestEventTest < self
    def test_multiple_commits
      event = JSON.parse(fixture_data("pull-request-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "pull-request",
            :record => fill_extra_fields(event) }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class CommitTest < self
    def test_commit
      commit = JSON.parse(fixture_data("commit.json"))
      push = JSON.parse(fixture_data("push-event.json"))
      push = fill_extra_fields(push)
      @crawler.process_commit(commit, push)

      expected_commit = JSON.parse(fixture_data("commit.json"))
      expected_push = JSON.parse(fixture_data("push-event.json"))

      expected_commit = fill_extra_fields(expected_commit, expected_push)

      expected_push["payload"]["commits"].each do |commit|
        commit["commit"] = expected_commit
      end
      expected_push = fill_extra_fields(expected_push)

      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "commit",
            :record =>  expected_commit },
          { :tag    => "push",
            :record => expected_push }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end
end
