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

require './include/ruby/misc'
require 'yaml'

$PROTON_MASS = 1.00727646677

$proteomicsKnowledge = Hash.new

File::open('include/proteomics-knowledge-base/amino-acids.csv', 'r') do |f|
    header = mapCsvHeader(f.readline)
    $proteomicsKnowledge[:aminoacids] = Hash.new
    f.each_line do |line|
        lineArray = line.parse_csv()
        $proteomicsKnowledge[:aminoacids][lineArray[header['singlelettercode']]] ||= Hash.new
        header.keys.each do |key|
            item = lineArray[header[key]]
            item = item.to_f if ['monoisotopicmass', 'averagemass'].include?(key)
            item = item.to_i if ['id'].include?(key)
            $proteomicsKnowledge[:aminoacids][lineArray[header['singlelettercode']]][key.intern] = item
        end
    end
end

File::open('include/proteomics-knowledge-base/isotopes.csv', 'r') do |f|
    header = mapCsvHeader(f.readline)
    $proteomicsKnowledge[:isotopes] = Hash.new
    f.each_line do |line|
        lineArray = line.parse_csv()
        element = lineArray[header['element']]
        isotope = lineArray[header['isotope']].to_i
        monoisotopicMass = lineArray[header['monoisotopicmass']].to_f
        abundance = lineArray[header['naturalabundance']].to_f
        $proteomicsKnowledge[:isotopes][element] ||= Hash.new
        $proteomicsKnowledge[:isotopes][element][isotope] ||= Hash.new
        $proteomicsKnowledge[:isotopes][element][isotope][:monoisotopicmass] = monoisotopicMass
        $proteomicsKnowledge[:isotopes][element][isotope][:abundance] = abundance
    end
end

File::open('include/proteomics-knowledge-base/genetic-codes.txt', 'r') do |f|
    goodLines = []
    f.each_line do |line|
        line.strip!
        next if line.empty? || line[0, 1] == '#'
        goodLines << line
    end
    $proteomicsKnowledge[:geneticCodes] = Hash.new
    $proteomicsKnowledge[:geneticCodes][1] = Hash.new
    goodLines.delete_at(0)
    (0..4).each do |i|
        goodLines[i] = goodLines[i][-64, 64]
    end
    (0...64).each do |i|
        triplet = ''
        (0...3).each do |k|
            triplet += goodLines[2 + k][i, 1]
        end
        $proteomicsKnowledge[:geneticCodes][1][triplet] = goodLines[0][i, 1]
    end
end

$proteomicsKnowledge[:isotopes].keys.each do |element|
    lightestIsotope = $proteomicsKnowledge[:isotopes][element].keys.sort.first
    $proteomicsKnowledge[:isotopes][element][:default] = $proteomicsKnowledge[:isotopes][element][lightestIsotope].dup
end


def elementMass(element)
    return $proteomicsKnowledge[:isotopes][element][:default][:monoisotopicmass]
end


def aminoAcidMass(aa)
     return $proteomicsKnowledge[:aminoacids][aa][:monoisotopicmass]
end


def peptideMass(peptide)
    mass = elementMass('H') * 2.0 + elementMass('O')
    (0...peptide.size).each do |i|
        mass += aminoAcidMass(peptide[i, 1])
    end
    return mass
end


def translateDna(dna)
    result = ''
    i = 0
    while i + 2 < dna.length 
        triplet = dna[i, 3]
        result += $proteomicsKnowledge[:geneticCodes][1][triplet]
        i += 3
    end
    return result
end
