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

Gem::Specification.new do |spec|
  spec.name = "fluent-plugin-github-activities"
  spec.version = "0.1.0"
  spec.authors = ["YUKI Hiroshi"]
  spec.email = ["yuki@clear-code.com"]
  spec.summary = "Fluentd plugin to crawl public activities on the GitHub."
  spec.description = "This provides ability you fluentd to crawl public " +
                       "activities of users."
  spec.homepage = "https://github.com/groonga/fluent-plugin-groonga"
  spec.license = "LGPL-3.0"

  spec.files = ["README.md", "Gemfile", "#{spec.name}.gemspec"]
  spec.files += Dir.glob("lib/**/*.rb")
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency("fluentd")

  spec.add_development_dependency("rake")
  spec.add_development_dependency("bundler")
end
