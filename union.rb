# Copyright (c) 2010 Michael Specht
# 
# This file is part of Proteomatic.
# 
# Proteomatic is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# Proteomatic is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with Proteomatic.  If not, see <http://www.gnu.org/licenses/>.

require 'include/ruby/proteomatic'
require 'set'


class Union < ProteomaticScript
	def run()
        entries = Set.new
        @input[:entries].each do |path|
            thisEntries = Set.new(File::read(path).split("\n"))
            entries |= thisEntries
        end
        puts "Unified entries: #{entries.size}."
        if @output[:union]
            File::open(@output[:union], 'w') do |f|
                f.puts entries.to_a.join("\n")
            end
        end
    end
end

lk_Object = Union.new