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
    @crawler = ::Fluent::GithubActivities::Crawler.new(:request_queue => @request_queue)
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
end
