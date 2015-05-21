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

require "fluent/plugin/github-activities"

class CrawlerTest < Test::Unit::TestCase
  def setup
    @request_queue = []
    @emitted_records = []

    @crawler = ::Fluent::GithubActivities::Crawler.new(:request_queue => @request_queue)
    @crawler.on_emit = lambda do |tag, record|
      @emitted_records << { :tag    => tag,
                            :record => record }
    end
  end

  data(
    :user_events => {
      :request => { :type => ::Fluent::GithubActivities::TYPE_EVENTS,
                    :user => "username" },
      :uri => "https://api.github.com/users/username/events/public",
    },
  )
  def test_request_uri(data)
    uri = @crawler.request_uri(data[:request])
    assert_equal(URI(data[:uri]), uri)
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
                   { :request_queue   => @request_queue,
                     :emitted_records => @emitted_records })
    end
  end

  class UserEventsTest < self
    def test_generic
      @crawler.process_user_events("username", [{ "type" => "test" }])
      expected = {
        :request_queue => [
          { :type => ::Fluent::GithubActivities::TYPE_EVENTS,
            :user => "username" },
        ],
        :emitted_records => [
          { :tag    => "test",
            :record => { "type" => "test" } },
        ],
      }
      assert_equal(expected,
                   { :request_queue   => @request_queue,
                     :emitted_records => @emitted_records })
    end
  end
end
