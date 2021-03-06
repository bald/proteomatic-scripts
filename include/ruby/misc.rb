# Copyright (c) 2007-2008 Michael Specht
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

require './include/ruby/ext/fastercsv'


def meanAndSd(ak_Values)
    ld_Mean = 0.0
    ld_Sd = 0.0
    
    lb_AllInfinity = true
    ak_Values.each do |x|
        unless x == 1.0 / 0.0
            lb_AllInfinity = false
            break
        end
    end
    if lb_AllInfinity
        return 1.0 / 0.0, nil
    end
    
    ak_Values.each { |x| ld_Mean += x }
    ld_Mean /= ak_Values.size
    
    ak_Values.each { |x| ld_Sd += ((x - ld_Mean) ** 2.0) }
    ld_Sd /= ak_Values.size
    
    begin
        ld_Sd = Math.sqrt(ld_Sd)
    rescue StandardError => e
        return nil, nil
    end
    
    return ld_Mean, ld_Sd
end


def stddev(ak_Values)
    mean, sd = meanAndSd(ak_Values)
    return sd
end


# calculates median of values
def median(ak_Values)
    median, iqr = medianAndIqr(ak_Values)
    return median
end


# calculates median of values
def medianAndIqr(ak_Values)
    if ak_Values.size == 0
        raise StandardError("Cannot determine median of empty set of values.")
    end
    ak_Values.sort!
    p = [1, 2, 3].collect do |x|
        r = (x.to_f / 4.0) * (ak_Values.size - 1)
        (ak_Values[r.floor] + ak_Values[r.ceil]) * 0.5
    end
    return p[1], p[2] - p[0]
end


# calculates median of values
def quartiles(ak_Values)
    if ak_Values.size == 0
        raise StandardError("Cannot determine median of empty set of values.")
    end
    ak_Values.sort!
    return [1, 2, 3].collect do |x|
        r = (x.to_f / 4.0) * (ak_Values.size - 1)
        (ak_Values[r.floor] + ak_Values[r.ceil]) * 0.5
    end
end


def wordwrap(as_String, ai_MaxLength = 70)
	lk_RegExp = Regexp.new('.{1,' + ai_MaxLength.to_s + '}(?:\s|\Z)')
	as_String.gsub(/\t/,"     ").gsub(lk_RegExp){($& + 5.chr).gsub(/\n\005/,"\n").gsub(/\005/,"\n")}
end


def indent(as_String, ai_Indent = 4, ab_FirstLine = true)
	ls_Indent = ''
	ai_Indent.times { ls_Indent += ' ' }
	ls_FirstIndent = ''
	ls_FirstIndent = ls_Indent if ab_FirstLine
	ls_FirstIndent + as_String.gsub("\n", "\n" + ls_Indent)
end


def underline(as_String, ac_Char)
	ls_Result = as_String + "\n"
	as_String.length.times { ls_Result += ac_Char }
	ls_Result += "\n"
	return ls_Result
end


def bytesToString(ai_Size)
	if ai_Size < 1024
		return "#{ai_Size} bytes"
	elsif ai_Size < 1024 * 1024
		return "#{sprintf('%1.2f', ai_Size.to_f / 1024.0)} KiB"
    elsif ai_Size < 1024 * 1024 * 1024
        return "#{sprintf('%1.2f', ai_Size.to_f / 1024.0 / 1024.0)} MiB"
    elsif ai_Size < 1024 * 1024 * 1024 * 1024
        return "#{sprintf('%1.2f', ai_Size.to_f / 1024.0 / 1024.0 / 1024.0)} GiB"
	end
	return "#{sprintf('%1.2f', ai_Size.to_f / 1024.0 / 1024.0 / 1024.0 / 1024.0)} TiB"
end


def stringEndsWith(as_String, as_End, ab_CaseSensitive = true)
	return false if as_String.size < as_End.size
	if ab_CaseSensitive
		return (as_String[-as_End.size, as_End.size] <=> as_End) == 0
	else
		return as_End.casecmp(as_String[-as_End.size, as_End.size]) == 0
	end
end


def determinePlatform()
	case RUBY_PLATFORM.downcase
	when /linux/ then
		'linux'
	when /darwin/ then
		'macx'
	when /mswin/ then
		'win32'
    when /mingw/ then
        'win32'
	else
		puts "Internal error: #{RUBY_PLATFORM} platform not supported."
		exit 1
	end
end


def mergeCsvFiles(ak_Files, as_OutFilename)
	lk_File = File.open(ak_Files.first, 'r')
	# read header from first file
	ls_Header = lk_File.readline
	lk_File.close()
	
	lk_Out = File.open(as_OutFilename, 'w')
	lk_Out.write(ls_Header)
	
	ak_Files.each do |ls_Filename|
		lk_File = File.open(ls_Filename, 'r')
		# skip csv header
		lk_File.readline
		lk_Out.write(lk_File.read)
		lk_File.close()
	end
	
	lk_Out.close()
end


class String
	# 'Natural order' comparison of two strings
	def String.natcmp(str1, str2, caseInsensitive=false)
		str1, str2 = str1.dup, str2.dup
		compareExpression = /^(\D*)(\d*)(.*)$/
	
		if caseInsensitive
			str1.downcase!
			str2.downcase!
		end
	
		# Remove all whitespace
		str1.gsub!(/\s*/, '')
		str2.gsub!(/\s*/, '')
	
		while (str1.length > 0) or (str2.length > 0) do
			# Extract non-digits, digits and rest of string
			str1 =~ compareExpression
			chars1, num1, str1 = $1.dup, $2.dup, $3.dup
	
			str2 =~ compareExpression
			chars2, num2, str2 = $1.dup, $2.dup, $3.dup
	
			# Compare the non-digits
			case (chars1 <=> chars2)
				when 0 # Non-digits are the same, compare the digits...
					# If either number begins with a zero, then compare alphabetically,
					# otherwise compare numerically
					if (num1[0] != 48) and (num2[0] != 48)
						num1, num2 = num1.to_i, num2.to_i
					end
	
					case (num1 <=> num2)
						when -1 then return -1
						when 1 then return 1
					end
				when -1 then return -1
				when 1 then return 1
			end # case
	
		end # while
	
		# Strings are naturally equal
		return 0
	end
	
end # class String


def stripCsvHeader(header)
    header.dup.strip.downcase.gsub(/[\s\-\/#]/, '')
end


# split header, downcase and remove these: whitespace - /
# returns a hash of downcased-stripped-header -> index
def mapCsvHeader(as_Header, ak_Options = {})
	lk_Header = as_Header.parse_csv(ak_Options)
	lk_StrippedHeaderMap = Hash.new
	lk_HeaderMap = Hash.new
	(0...lk_Header.size).each do |i|
		next unless lk_Header[i]
		ls_Key = stripCsvHeader(lk_Header[i])
		lk_StrippedHeaderMap[ls_Key] = lk_Header[i]
		lk_HeaderMap[ls_Key] = i
	end
	return lk_HeaderMap
end


def loadCsvResults(as_Path)
	lk_HeaderMap = Hash.new
	lk_Result = Array.new
	File.open(as_Path, 'r') do |lk_File|
		ls_Header = lk_File.readline
		lk_HeaderMap = mapCsvHeader(ls_Header)

		while (!lk_File.eof?)
			lk_Result.push(lk_File.readline.parse_csv())
		end
	end
	return lk_HeaderMap, lk_Result
end


def printStyleSheet(ak_Target = $STDOUT)
	ak_Target.puts '<style type=\'text/css\'>'
	ak_Target.puts 'body {font-family: Verdana; font-size: 10pt;}'
	ak_Target.puts 'h1 {font-size: 14pt;}'
	ak_Target.puts 'h2 {font-size: 12pt; border-top: 1px solid #888; border-bottom: 1px solid #888; padding-top: 0.2em; padding-bottom: 0.2em; background-color: #e8e8e8; }'
	ak_Target.puts 'h3 {font-size: 10pt; }'
	ak_Target.puts 'h4 {font-size: 10pt; font-weight: normal;}'
	ak_Target.puts 'ul {padding-left: 0;}'
	ak_Target.puts 'ol {padding-left: 0;}'
	ak_Target.puts 'li {margin-left: 2em;}'
	ak_Target.puts '.default { }'
	ak_Target.puts '.nonDefault { background-color: #ada;}'
	ak_Target.puts 'table {border-collapse: collapse;} '
	ak_Target.puts 'table tr {text-align: left; font-size: 10pt;}'
	ak_Target.puts 'table th, table td {vertical-align: top; border: 1px solid #888; padding: 0.2em;}'
	ak_Target.puts 'table tr.sub th, table tr.sub td {vertical-align: top; border: 1px dashed #888; padding: 0.2em;}'
	ak_Target.puts 'table th {font-weight: bold;}'
	ak_Target.puts '.gpf-confirm { background-color: #aed16f; }'
	ak_Target.puts '.toggle { padding: 0.2em; border: 1px solid #888; background-color: #f0f0f0; }'
	ak_Target.puts '.toggle:hover { cursor: pointer; border: 1px solid #000; background-color: #ddd; }'
	ak_Target.puts '.clickableCell { text-align: center; }'
	ak_Target.puts '.clickableCell:hover { cursor: pointer; }'
	ak_Target.puts '</style>'
end


# returns pattern, items
def splitNumbersAndLetters(as_String)
	lk_Parts = Array.new
	ls_Pattern = ''
	(0...as_String.size).each do |i|
		ls_ThisPattern = '0123456789'.include?(as_String[i, 1]) ? '0' : 'a'
		unless ls_Pattern
			ls_Pattern += ls_ThisPattern
			lk_Parts << as_String[i, 1]
		end
		if ls_ThisPattern != ls_Pattern[-1, 1]
			ls_Pattern += ls_ThisPattern
			lk_Parts << as_String[i, 1]
		else
			lk_Parts[-1] += as_String[i, 1]
		end
	end
	return ls_Pattern, lk_Parts
end

def readData(id = nil)
	DATA.rewind
	s = DATA.read
	return s unless id
	startIndex = s.index('__' + id.upcase + '__')
	return '' unless startIndex
	endIndex = s.index('__' + id.upcase + '__', startIndex + 1)
	return '' unless endIndex
	return s[startIndex + id.size + 4, endIndex - startIndex - id.size - 4]
end


# Returns distinct ordered CSV headers from all CSV files in fileList.
# By default, headers are stripped and simplified before comparison
def allCsvHeaders(fileList, useStrippedHeader = true)
    distinctHeaderLists = Set.new
    fileList.each do |path|
        File::open(path, 'r') do |f|
            headerLine = f.readline
            headerList = headerLine.parse_csv()
            thisColumns = []
            if useStrippedHeader
                headerList.each { |x| thisColumns << stripCsvHeader(x) }
            else
                headerList.each { |x| thisColumns << x }
            end
            distinctHeaderLists << thisColumns
        end
    end
    return distinctHeaderLists
end
