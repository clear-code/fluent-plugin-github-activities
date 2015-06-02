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

    @crawler = ::Fluent::GithubActivities::Crawler.new
    @crawler.on_emit = lambda do |tag, record|
      @emitted_records << { :tag    => tag,
                            :record => record }
    end
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
      @crawler.process_user_event("username", { "type" => "test" })
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "test",
            :record => { "type" => "test" } },
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class UserEventsTest < self
    def test_generic
      @crawler.process_user_events("username", [{ "type" => "test" }])
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "test",
            :record => { "type" => "test" } },
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class PushEventTest < self
    def test_multiple_commits
      event = JSON.parse(fixture_data("push-event-multiple-commits.json"))
      base = "https://api.github.com/repos/clear-code/fluent-plugin-github-activities/commits"
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/8e90721ff5d89f52b5b3adf0b86db01f03dc5588"},
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/63e085b7607a3043cfbf9a866561807fbdda8a10"},
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/c85e33bace040b7b42983e14d2b11a491d102072"},
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/8ce6de7582376187e17e233dbae13575311a8c0b"},
          { :type => ::Fluent::GithubActivities::TYPE_COMMIT,
            :uri  => "#{base}/c908f319c7b6d5c5a69c8b675bde40dd990ee364"},
        ],
        :emitted_records => [
          { :tag    => "push",
            :record => event }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class IssuesEventTest < self
    def test_multiple_commits
      event = JSON.parse(fixture_data("issues-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "issues",
            :record => event }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class IssueCommentEventTest < self
    def test_multiple_commits
      event = JSON.parse(fixture_data("issue-comment-event.json"))
      @crawler.process_user_event("user", event)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "issue-comment",
            :record => event }
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
            :record => event }
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
            :record => event }
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
            :record => event }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class CommitTest < self
    def test_multiple_commits
      commit = JSON.parse(fixture_data("commit.json"))
      push = JSON.parse(fixture_data("push-event.json"))
      @crawler.process_commit(commit, push)
      expected = {
        :request_queue => [],
        :emitted_records => [
          { :tag    => "commit",
            :record => commit }
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @crawler.request_queue,
                     :emitted_records => @emitted_records })
    end
  end
end
