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

require "pathname"
require "fileutils"
require "tempfile"

module Fluent
  module Plugin
  module GithubActivities
    class SafeFileWriter
      class << self
        def write(path, contents=nil)
          # Don't output the file directly to prevent loading of incomplete file!
          path = Pathname(path).expand_path
          FileUtils.mkdir_p(path.dirname.to_s)
          Tempfile.open(path.basename.to_s, path.dirname.to_s) do |output|
            if block_given?
              yield(output, output.path)
            else
              output.write(contents)
            end
            output.flush
            File.rename(output.path, path.to_s)
          end
        end
      end
    end
  end
  end
end

