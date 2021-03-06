#! /usr/bin/env ruby
# Copyright (c) 2007-2010 Michael Specht
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

require './include/ruby/proteomatic'
require './include/ruby/evaluate-omssa-helper'
require './include/ruby/ext/fastercsv'
require './include/ruby/misc'
require 'set'
require 'yaml'

class WriteOmssaReport < ProteomaticScript
    
    def formatProtein(protein)
        if protein[0, 9] == '__group__'
            entries = protein.sub('__group__', '').split("\01")
            # remove all GPF peptides from group
            entries = entries.select do |x|
                x.index(@param[:putativePrefix] + 'gpf_') != 0
            end
            if entries.size == 1
                protein = entries.first
                # and continue below...
            else
                if entries.size == 0
                    entries = protein.sub('__group__', '').split("\01")
                end
                return "<b>protein group</b> (#{entries.size} proteins)<br /><ul>" + entries.collect do |x| 
                    y = ''
                    if @hasProteinGroups
                        y = ' <b><i>(not unique)</i></b>' if @proteinGroupsForProteinNoPutative[x].size > 1
                    end
                    '<li>' + x + y + '</li>'
                end.join("\n") + '</ul>'
            end
        end
        y = ''
        if @hasProteinGroups && protein[0, 9] != '__group__'
            unless @proteinGroupsForProteinNoPutative.include?(protein)
                puts "AAAAAAHH"
                puts protein
                exit
            end
            y = ' <b><i>(not unique)</i></b>' if @proteinGroupsForProteinNoPutative[protein].size > 1
        end
        return protein + y
    end
    
    def run()
        
        @proteinGroupsForProtein = Hash.new
        @proteinGroupsForProteinNoPutative = Hash.new
        @hasProteinGroups = false
        # merge OMSSA results
        lk_Result = loadPsm(@input[:psmFile].first, {:putativePrefix => @param[:putativePrefix]})
        
        lk_ScanHash = lk_Result[:scanHash]
        lk_PeptideHash = lk_Result[:peptideHash]
        lk_GpfPeptides = lk_Result[:gpfPeptides]
        lk_ModelPeptides = lk_Result[:modelPeptides]
        lk_ProteinIdentifyingModelPeptides = lk_Result[:proteinIdentifyingModelPeptides]
        lk_Proteins = lk_Result[:proteins]
        lk_ScoreThresholds = lk_Result[:scoreThresholds]
        lk_ActualFpr = lk_Result[:actualFpr]
        lk_SpectralCounts = lk_Result[:spectralCounts]
        allDefLines = lk_Result[:allDefLines]
        
        allDefLines.each do |protein|
            if protein[0, 9] == '__group__'
                @hasProteinGroups = true
                break
            end
        end
        
        if @hasProteinGroups
            allDefLines.each do |protein|
                if protein[0, 9] == '__group__'
                    entries = protein.sub('__group__', '').split("\01")
                    entries.each do |entry|
                        @proteinGroupsForProtein[entry] ||= Set.new
                        @proteinGroupsForProtein[entry] << protein
                        @proteinGroupsForProteinNoPutative[entry] ||= Set.new
                        @proteinGroupsForProteinNoPutative[entry] << protein unless protein[0, @param[:putativePrefix].size] == @param[:putativePrefix]
                    end
                else
                    @proteinGroupsForProtein[protein] ||= Set.new
                    @proteinGroupsForProtein[protein] << protein
                    @proteinGroupsForProteinNoPutative[protein] ||= Set.new
                    @proteinGroupsForProteinNoPutative[protein] << protein unless protein[0, @param[:putativePrefix].size] == @param[:putativePrefix]
                end
            end
        end
        
        # if we have protein groups, denote for every protein whether it is unique
        # unique means that when you see this protein, it does not appear in other
        # protein groups or as a single protein
        # denote by <b><i>(not unique)</i></b>
        
        lk_ProteinsBySpectralCount = lk_Proteins.keys.sort { |a, b| lk_SpectralCounts[:proteins][b][:total] <=> lk_SpectralCounts[:proteins][a][:total]}
        lk_AmbiguousPeptides = (lk_ModelPeptides - lk_ProteinIdentifyingModelPeptides).to_a.sort! do |x, y|
            lk_PeptideHash[x][:scans].size == lk_PeptideHash[y][:scans].size ? x <=> y : lk_PeptideHash[y][:scans].size <=> lk_PeptideHash[x][:scans].size
        end

        puts "Unique peptides identified: #{lk_PeptideHash.size}."
        puts "Peptides found by both GPF and models: #{(lk_GpfPeptides & lk_ModelPeptides).size}."
        puts "Peptides found by GPF alone: #{(lk_GpfPeptides - lk_ModelPeptides).size}."
        puts "Peptides found by models alone: #{(lk_ModelPeptides - lk_GpfPeptides).size}."
        puts "Model peptides that identify a protein: #{lk_ProteinIdentifyingModelPeptides.size}"
        puts "Model peptides that appear in more than one protein: #{(lk_ModelPeptides - lk_ProteinIdentifyingModelPeptides).size}."
        puts "Proteins identified: #{lk_Proteins.size}."
        
        if @output[:htmlReport]
            File.open(@output[:htmlReport], 'w') do |lk_Out|
                lk_Spots = Hash.new()
                lk_ScanHash.keys.each do |ls_Scan|
                    lk_ScanParts = ls_Scan.split('.')
                    ls_Spot = lk_ScanParts.slice(0, lk_ScanParts.size - 3).join('.')
                    lk_Spots[ls_Spot] ||= Array.new
                    lk_Spots[ls_Spot].push(ls_Scan)
                end
                lk_SpotKeys = lk_Spots.keys
                lk_SpotKeys.sort! { |x, y| String::natcmp(x, y) }
                
                lk_Out.puts '<html>'
                lk_Out.puts '<head>'
                lk_Out.puts '<title>OMSSA Report</title>'
                lk_Out.puts '<style type=\'text/css\'>'
                lk_Out.puts 'body {font-family: Verdana; font-size: 10pt;}'
                lk_Out.puts 'h1 {font-size: 14pt;}'
                lk_Out.puts 'h2 {font-size: 12pt; border-top: 1px solid #888a85; border-bottom: 1px solid #888a85; padding-top: 0.2em; padding-bottom: 0.2em; background-color: #eeeeec; }'
                lk_Out.puts 'h3 {font-size: 10pt; }'
                lk_Out.puts 'h4 {font-size: 10pt; font-weight: normal;}'
                lk_Out.puts 'ul {padding-left: 0;}'
                lk_Out.puts 'ol {padding-left: 0;}'
                lk_Out.puts 'li {margin-left: 2em;}'
                lk_Out.puts '.default { }'
                lk_Out.puts 'table {border-collapse: collapse;} '
                lk_Out.puts 'table tr {text-align: left; font-size: 10pt;}'
                lk_Out.puts 'table th, td {vertical-align: top; border: 1px solid #888a85; padding: 0.2em;}'
                lk_Out.puts 'table th {font-weight: bold;}'
                lk_Out.puts '.gpf-confirm { background-color: #a6cc82; }'
                lk_Out.puts '.toggle { cursor: pointer; text-decoration: underline; color: #babdb6; }'
                lk_Out.puts '.toggle:hover { color: #000; }'
                lk_Out.puts '</style>'
                lk_Out.puts "<script type='text/javascript'>"
                lk_Out.puts "/*<![CDATA[*/"
                lk_Out.puts "function toggle(as_Name, as_Display) {"
                lk_Out.puts "lk_Elements = document.getElementsByClassName(as_Name);"
                lk_Out.puts "for (var i = 0; i < lk_Elements.length; ++i)"
                lk_Out.puts "lk_Elements[i].style.display = lk_Elements[i].style.display == 'none' ? as_Display : 'none';"
                lk_Out.puts "}"
                lk_Out.puts "/*]]>*/"
                lk_Out.puts "</script>"
                lk_Out.puts '</head>'
                lk_Out.puts '<body>'
                lk_Out.puts '<h1>OMSSA Report</h1>'
                lk_Out.puts '<h2>Contents</h2>'
                lk_Out.puts '<ol>'
                lk_SpotLinks = Array.new
                lk_SpotKeys.each { |ls_Spot| lk_SpotLinks.push("<a href='#subheader-spot-#{ls_Spot}'>#{ls_Spot}</a>") }
                
                lk_Out.puts "<li><a href='#header-overview-and-statistical-significance'>Overview and statistical significance</a></li>"
                lk_Out.puts "<li><a href='#header-identified-proteins-by-spectral-count'>Identified proteins by spectral count</a></li>" if @param[:writeIdentifiedProteinsBySpectralCount]
                lk_Out.puts "<li><a href='#header-identified-proteins-by-spot'>Identified proteins by spot</a> <span class='toggle' onclick='toggle(\"toc-proteins-by-spot-spots\", \"inline\")'>[show spots]</span><span class='toc-proteins-by-spot-spots' style='display: none;'><br />(#{lk_SpotLinks.join(', ')})</span></li>" if @param[:writeIdentifiedProteinsBySpot] && lk_SpotKeys.size > 1
                lk_Out.puts "<li><a href='#header-identified-proteins-by-distinct-peptide-count'>Identified proteins by distinct peptide count</a></li>" if @param[:writeIdentifiedProteinsByDistinctPeptideCount]
                lk_Out.puts "<li><a href='#header-new-gpf-peptides'>Additional peptides identified by GPF</a></li>" if (lk_GpfPeptides - lk_ModelPeptides).size > 0 && @param[:writeAdditionalPeptidesIdentifiedByGPF]
                lk_Out.puts "<li><a href='#header-ambiguous-peptides'>Identified peptides that appear in more than one model protein</a></li>" if (lk_ModelPeptides - lk_ProteinIdentifyingModelPeptides).size > 0 && @param[:writeAmbiguousPeptides]
                lk_Out.puts "<li><a href='#header-modified-peptides'>Modified peptides</a></li>" if @param[:writeModifiedPeptides]
                lk_Out.puts "<li><a href='#header-all-identified-peptides'>All identified peptides</a></li>" if @param[:writeAllIdentifiedPeptides]
                lk_Out.puts '</ol>'
            
                lk_Out.puts "<h2 id='header-overview-and-statistical-significance'>Overview and statistical significance</h2>"
                lk_Out.puts '<p>'
                lk_Out.puts "Number of distinct peptides identified: #{lk_PeptideHash.keys.size}.<br />"
                lk_Out.puts "Number of distinct peptides that unambiguously identify a gene model: #{lk_ProteinIdentifyingModelPeptides.size}.<br />"
                lk_Out.puts "Number of proteins identified: #{lk_Proteins.size}.<br />"
                lk_Out.puts '</p>'
                lk_Out.puts '<h3>Statistical significance</h3>'
                if (lk_Result[:scoreThresholdType] == 'fpr')
                    lk_Out.puts "<p>The results presented in this report have been conjured via a target-decoy approach, all resulting <acronym title='peptide-spectral matches'>PSM</acronym> have been cropped with a target <acronym title='false positive rate'>FPR</acronym> of #{sprintf('%1.2f', lk_Result[:targetFpr] * 100.0)}%. "
                    if lk_Result[:hasGlobalFpr]
                        lk_Out.puts "The score threshold has been determined globally."
                    else
                        lk_Out.puts "The score thresholds have been determined individually for each spot."
                    end
                    lk_Out.puts "</p>"
                    lk_Out.puts '<table>'
                    lk_Out.puts '<thead>'
                    lk_Out.puts '<tr><th>Spot</th><th>E-value threshold</th><th>Actual FPR</th></tr>'
                    lk_Out.puts '</thead>'
                    lk_Out.puts '<tbody>'
                    lk_ScoreThresholds.keys.sort { |a, b| String::natcmp(a, b) }.each do |ls_Spot|
                        lb_Good = false
                        lb_Good = true if lk_ActualFpr[ls_Spot] && lk_ActualFpr[ls_Spot] <= lk_Result[:targetFpr]
                        lk_Out.puts "<tr style='background-color: #{lb_Good ? '#a6cc82' : '#f79494'};'><td>#{ls_Spot}</td><td>#{lk_ScoreThresholds[ls_Spot] ? sprintf('%e', lk_ScoreThresholds[ls_Spot]) : 'n/a'}</td><td>#{lk_ActualFpr[ls_Spot] ? sprintf('%1.2f%%', lk_ActualFpr[ls_Spot] * 100.0) : 'n/a'}</td></tr>"
                    end
                    lk_Out.puts '</tbody>'
                    lk_Out.puts '</table>'
                elsif (lk_Result[:scoreThresholdType] == 'min' || lk_Result[:scoreThresholdType] == 'max')
                    lk_Out.puts "<p>The results presented in this report have been filtered with a fixed score threshold of #{sprintf('%1.2e', lk_Result[:scoreThresholds].values.first)}."
                    lk_Out.puts "</p>"
                else
                    lk_Out.puts "<p>Information about the statistical significance of the results is unavailable.</p>"
                end
                if @hasProteinGroups
                    lk_Out.puts '<h3>Protein groups</h3>'
                    lk_Out.puts "These results contain protein groups."
                    notUniqueProteins = Array.new
                    @proteinGroupsForProteinNoPutative.each_pair do |protein, entries|
                        next if protein.index(@param[:putativePrefix] + 'gpf_') == 0
                        notUniqueProteins << protein if entries.size > 1
                    end
                    unless notUniqueProteins.empty?
                        lk_Out.puts "There are #{notUniqueProteins.size} proteins that appear in multiple protein groups and/or as a single protein, these proteins have been marked as <b><i>(not unique)</i></b>.<br />"
                        lk_Out.puts "<ul>"
                        notUniqueProteins.each do |protein|
                            lk_Out.puts "<li>#{formatProtein(protein)}</li>"
                        end
                        lk_Out.puts "</ul>"
                    else
                        lk_Out.puts "Still, all proteins are unique, regardless of whether they are grouped or not, and can be regarded as unique identifications."
                    end
                end
                
                if @param[:writeIdentifiedProteinsBySpectralCount]
                    lk_Out.puts "<h2 id='header-identified-proteins-by-spectral-count'>Identified proteins by spectral count</h2>"
                    
                    lk_Out.puts "<p>"
                    lk_Out.puts "This table contains all model proteins that could be identified, sorted by spectral count. "
                    lk_Out.puts "Peptides that have additionally been found by de novo prediction and GPF search are <span class='gpf-confirm'>highlighted</span>." unless lk_GpfPeptides.empty?
                    lk_Out.puts "</p>"
                    
                    lk_Out.puts '<table>'
                    lk_Out.puts '<thead>'
                    lk_Out.puts "<tr><th>Protein</th><th>Protein spectral count</th><th>Peptides</th><th>Peptide spectral count</th></tr>"
                    lk_Out.puts '</thead>'
                    lk_Out.puts '<tbody>'
                    lk_Out.print '<tr>'
                    
                    lb_Open0 = true
                    li_ToggleCounter = 0
                    lk_ProteinsBySpectralCount.each do |ls_Protein|
                        lb_Open1 = true
                        lk_Out.print "<tr>" unless lb_Open0
                        lk_FoundInSpots = Set.new
                        lk_Proteins[ls_Protein].each do |ls_Peptide|
                            lk_FoundInSpots.merge(lk_PeptideHash[ls_Peptide][:spots])
                        end
                        lk_FoundInSpots = lk_FoundInSpots.to_a
                        lk_FoundInSpots.sort! { |x, y| String::natcmp(x, y) }
                        lk_FoundInSpots.collect! { |x| "<a href='#subheader-spot-#{x}'>#{x}</a> (#{lk_SpectralCounts[:proteins][ls_Protein][x]})" }
                        ls_FoundInSpots = lk_FoundInSpots.join(', ')
                        li_ToggleCounter += 1
                        ls_ToggleClass = "proteins-by-spectral-count-#{li_ToggleCounter}"
                        lk_Out.print "<td rowspan='#{lk_Proteins[ls_Protein].size}'>#{formatProtein(ls_Protein)} "
                        lk_Out.print "<i>(<span class='toggle' onclick='toggle(\"#{ls_ToggleClass}\", \"inline\")'>found in:</span><span class='#{ls_ToggleClass}' style='display: none;'> #{ls_FoundInSpots}</span>)</i>" if lk_SpotKeys.size > 1
                        lk_Out.print "</td>"
                        lk_Out.print "<td rowspan='#{lk_Proteins[ls_Protein].size}'>#{lk_SpectralCounts[:proteins][ls_Protein][:total]}</td>"
                        lk_PeptidesSorted = lk_Proteins[ls_Protein].sort { |x, y| lk_SpectralCounts[:peptides][y][:total] <=> lk_SpectralCounts[:peptides][x][:total]}
                        lk_PeptidesSorted.each do |ls_Peptide|
                            lk_Out.print "<tr>" unless lb_Open1
                            ls_CellStyle = lk_PeptideHash[ls_Peptide][:found][:gpf]? ' class=\'gpf-confirm\'' : ''
                            lb_FoundUnmodified = lk_PeptideHash[ls_Peptide][:foundUnmodified]
                            lb_FoundModified = !lk_PeptideHash[ls_Peptide][:mods].empty?
                            lk_Out.print "<td><span#{ls_CellStyle}>#{ls_Peptide}</span> #{(lb_FoundModified) ? '(<a href=\'#modified-peptide-' + ls_Peptide + '\' class=\'toggle\'>modified</a>' + (lb_FoundUnmodified ? ' and unmodified' : '') + ')</span>' : ''}</td><td>#{lk_SpectralCounts[:peptides][ls_Peptide][:total]}</td></tr>\n"
                            lb_Open0 = false
                            lb_Open1 = false
                        end
                    end
                    lk_Out.puts '</tbody>'
                    lk_Out.puts '</table>'
                end
                
                if @param[:writeIdentifiedProteinsBySpot] && lk_SpotKeys.size > 1
                    lk_Out.puts "<h2 id='header-identified-proteins-by-spot'>Identified proteins by spot</h2>"
                    lk_Out.puts "<p>"
                    lk_Out.puts "This table contains all model proteins that could be identified, sorted by spot. "
                    lk_Out.puts "Peptides that have additionally been found by de novo prediction and GPF search are <span class='gpf-confirm'>highlighted</span>." unless lk_GpfPeptides.empty?
                    lk_Out.puts "</p>"
                    
                    lk_Out.puts '<table>'
                    lk_Out.puts '<thead>'
                    lk_Out.puts '<tr><th>Protein</th><th>Protein spectral count</th><th>Peptides</th><th>Peptide spectral count</th></tr>'
                    lk_Out.puts '</thead>'
                    lk_Out.puts '<tbody>'
                    lk_SpotKeys.each do |ls_Spot|
                #WLQYSEVIHAR:
                #  scans: [MT_HydACPAN_1_300407.100.100.2, ...]
                #  spots: (MT_HydACPAN_1_300407) (set)
                #  found: {gpf, models}
                #  proteins: {x => true, y => true}
                        lk_SpotProteins = Hash.new
                        lk_ProteinIdentifyingModelPeptides.each do |ls_Peptide|
                            lk_Peptide = lk_PeptideHash[ls_Peptide]
                            next unless lk_Peptide[:spots].include?(ls_Spot)
                            li_PeptideCount = lk_Peptide[:scans].select { |x| x[0, ls_Spot.size] == ls_Spot }.size
                            lk_Peptide[:proteins].keys.each do |ls_Protein|
                                lk_SpotProteins[ls_Protein] ||= Hash.new
                                lk_SpotProteins[ls_Protein][:peptides] ||= Hash.new
                                lk_SpotProteins[ls_Protein][:peptides][ls_Peptide] ||= 0
                                lk_SpotProteins[ls_Protein][:peptides][ls_Peptide] += li_PeptideCount
                                lk_SpotProteins[ls_Protein][:count] ||= 0
                                lk_SpotProteins[ls_Protein][:count] += li_PeptideCount
                            end
                        end
                        #lk_Out.puts "<h3 id='subheader-spot-#{ls_Spot}'>#{ls_Spot}</h3>"
                        #lk_Out.puts "<tr id='subheader-spot-#{ls_Spot}'><td style='border-style: none; background-color: #fff; padding-top: 2em; padding-bottom: 1em;' colspan='4'><span style='font-weight: bold;'>#{ls_Spot}</span></td></tr>"
                        lk_Out.puts "<tr><td style='border: none' colspan='4'></td></tr>"
                        lk_Out.puts "<tr id='subheader-spot-#{ls_Spot}' style='background-color: #eee;'>"
                        lk_Out.puts "<td colspan='4'><b>#{ls_Spot}</b></td>"
                        lk_Out.puts "</tr>"
                        lk_Out.print '<tr>'
                        lb_Open0 = true
                        lk_SpotProteinsSorted = lk_SpotProteins.keys.sort { |x, y| lk_SpotProteins[y][:count] <=> lk_SpotProteins[x][:count] }
                        lk_SpotProteinsSorted.each do |ls_Protein|
                            lb_Open1 = true
                            lk_Out.print "<tr>" unless lb_Open0
                            lk_Out.print "<td rowspan='#{lk_SpotProteins[ls_Protein][:peptides].size}'>#{formatProtein(ls_Protein)}</td>"
                            lk_Out.print "<td rowspan='#{lk_SpotProteins[ls_Protein][:peptides].size}'>#{lk_SpotProteins[ls_Protein][:count]}</td>"
                            lk_PeptidesSorted = lk_SpotProteins[ls_Protein][:peptides].keys.sort { |x, y| lk_SpotProteins[ls_Protein][:peptides][y] <=> lk_SpotProteins[ls_Protein][:peptides][x]}
                            lk_PeptidesSorted.each do |ls_Peptide|
                                lk_Out.print "<tr>" unless lb_Open1
                                ls_CellStyle = lk_PeptideHash[ls_Peptide][:found][:gpf]? ' class=\'gpf-confirm\'' : ''
                                lk_Out.print "<td><span#{ls_CellStyle}>#{ls_Peptide}</span> #{(!lk_PeptideHash[ls_Peptide][:mods].empty?) ? '<a href=\'#modified-peptide-' + ls_Peptide + '\' class=\'toggle\'>[mods]</span>' : ''}</td><td>#{lk_SpotProteins[ls_Protein][:peptides][ls_Peptide]}</td></tr>\n"
                                lb_Open0 = false
                                lb_Open1 = false
                            end
                        end
                    end
                    lk_Out.puts '</tbody>'
                    lk_Out.puts '</table>'
                end
                
                if @param[:writeIdentifiedProteinsByDistinctPeptideCount]
                    lk_Out.puts "<h2 id='header-identified-proteins-by-distinct-peptide-count'>Identified proteins by distinct peptide count</h2>"
                    lk_Out.puts "<p>This table contains all model proteins that could be identified, sorted by the number of distinct peptides that identified the protein.</p>"
                    
                    lk_ProteinsByDistinctPeptideCount = lk_Proteins.keys.sort { |a, b| lk_Proteins[b].size <=> lk_Proteins[a].size}
                    lk_Out.puts '<table>'
                    lk_Out.puts '<thead>'
                    lk_Out.puts '<tr><th>Protein</th><th>Distinct peptide count</th><th>Peptides</th></tr>'
                    lk_Out.puts '</thead>'
                    lk_Out.puts '<tbody>'
                    lk_ProteinsByDistinctPeptideCount.each do |ls_Protein|
                        lk_Out.puts "<tr><td>#{formatProtein(ls_Protein)}</td><td>#{lk_Proteins[ls_Protein].size}</td><td>#{lk_Proteins[ls_Protein].sort.collect { |x| '<span ' + (ls_CellStyle = lk_PeptideHash[x][:found][:gpf]? ' class=\'gpf-confirm\'' : '') + '>' + x + '</span>'}.join(', ')}</td></tr>"
                    end
                    lk_Out.puts '</tbody>'
                    lk_Out.puts '</table>'
                end
                
                
                if @param[:writeAdditionalPeptidesIdentifiedByGPF]
                    if (lk_GpfPeptides - lk_ModelPeptides).size > 0
                        lk_Out.puts "<h2 id='header-new-gpf-peptides'>Additional peptides identified by GPF</h2>" 
                        lk_Out.puts '<p>These peptides have been significantly identified by de novo prediction and an error-tolerant GPF search, which means that these identified peptides are very probably correct although they are not part of the gene models used for the search.</p>'
                        lk_GpfOnlyPeptides = (lk_GpfPeptides - lk_ModelPeptides).to_a.sort! do |x, y|
                            lk_PeptideHash[x][:scans].size == lk_PeptideHash[y][:scans].size ? x <=> y : lk_PeptideHash[y][:scans].size <=> lk_PeptideHash[x][:scans].size
                        end
                        lk_Out.puts '<table>'
                        lk_Out.puts '<thead>'
                        lk_Out.puts '<tr><th>Scan count</th><th>Peptide</th><th>Scan</th><th>E-value</th></tr>'
                        lk_Out.puts '</thead>'
                        lk_Out.puts '<tbody>'
                        lk_GpfOnlyPeptides.each do |ls_Peptide|
                            li_ScanCount = lk_PeptideHash[ls_Peptide][:scans].size
                            lk_Out.puts "<tr><td rowspan='#{li_ScanCount}'>#{li_ScanCount}</td><td rowspan='#{li_ScanCount}'>#{ls_Peptide} #{(!lk_PeptideHash[ls_Peptide][:mods].empty?) ? '<a href=\'#modified-peptide-' + ls_Peptide + '\' class=\'toggle\'>[mods]</span>' : ''}</td><td>#{lk_PeptideHash[ls_Peptide][:scans].first}</td><td>#{sprintf('%e', lk_ScanHash[lk_PeptideHash[ls_Peptide][:scans].first][:e])}</td></tr>"
                            (1...li_ScanCount).each do |i|
                                lk_Out.puts "<tr><td>#{lk_PeptideHash[ls_Peptide][:scans][i]}</td><td>#{sprintf('%e', lk_ScanHash[lk_PeptideHash[ls_Peptide][:scans][i]][:e])}</td></tr>"
                            end
                        end
                        lk_Out.puts '</tbody>'
                        lk_Out.puts '</table>'
                    end
                end

                if @param[:writeAmbiguousPeptides]
                    if (lk_ModelPeptides - lk_ProteinIdentifyingModelPeptides).size > 0
                        lk_Out.puts "<h2 id='header-ambiguous-peptides'>Identified peptides that appear in more than one model protein</h2>"
                        lk_Out.puts "<p>"
                        lk_Out.puts "These peptides have been significantly identified but could not be used to identify a protein because they appear in multiple proteins. The following table can sometimes be used to detect redundancies in the protein database."
                        lk_Out.puts "Peptides that have additionally been found by de novo prediction and GPF searching are <span class=\'gpf-confirm\'>highlighted</span>." unless lk_GpfPeptides.empty?
                        lk_Out.puts "</p>"
                        lk_Out.puts '<table>'
                        lk_Out.puts '<thead>'
                        lk_Out.puts '<tr><th>Scan count</th><th>Peptide</th><th>Proteins</th><th>Scan</th><th>E-value</th></tr>'
                        lk_Out.puts '</thead>'
                        lk_Out.puts '<tbody>'
                        lk_AmbiguousPeptides.each do |ls_Peptide|
                            li_ScanCount = lk_PeptideHash[ls_Peptide][:scans].size
                            ls_CellStyle = lk_PeptideHash[ls_Peptide][:found][:gpf]? ' class=\'gpf-confirm\'' : ''
                            lk_Out.puts "<tr><td rowspan='#{li_ScanCount}'>#{li_ScanCount}</td><td rowspan='#{li_ScanCount}'><span#{ls_CellStyle}>#{ls_Peptide}</span> #{(!lk_PeptideHash[ls_Peptide][:mods].empty?) ? '<a href=\'#modified-peptide-' + ls_Peptide + '\' class=\'toggle\'>[mods]</span>' : ''}</td><td rowspan='#{li_ScanCount}'><ul>#{lk_PeptideHash[ls_Peptide][:proteins].keys.collect { |x| "<li>#{formatProtein(x)}</li>" }.join(' ')}</ul></td><td>#{lk_PeptideHash[ls_Peptide][:scans].first}</td><td>#{sprintf('%e', lk_ScanHash[lk_PeptideHash[ls_Peptide][:scans].first][:e])}</td></tr>"
                            (1...li_ScanCount).each do |i|
                                lk_Out.puts "<tr><td>#{lk_PeptideHash[ls_Peptide][:scans][i]}</td><td>#{sprintf('%e', lk_ScanHash[lk_PeptideHash[ls_Peptide][:scans][i]][:e])}</td></tr>"
                            end
                        end
                        lk_Out.puts '</tbody>'
                        lk_Out.puts '</table>'
                    end
                end
                
                if @param[:writeModifiedPeptides]
                    lk_Out.puts "<h2 id='header-modified-peptides'>Modified peptides</h2>"
                    lb_FoundAny = false
                    lk_PeptideHash.keys.sort.each do |ls_Peptide|
                        next if lk_PeptideHash[ls_Peptide][:mods].empty?
                        
                        li_PeptideRowCount = 0
                        lk_PeptideHash[ls_Peptide][:mods].keys.each do |ls_ModifiedPeptide|
                            lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide].keys.each do |ls_Description|
                                lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide][ls_Description].keys.each do |ls_Spot|
                                    li_PeptideRowCount += 1
                                end
                            end
                        end
                        lb_PeptideRow = true
                        
                        lk_PeptideHash[ls_Peptide][:mods].keys.each do |ls_ModifiedPeptide|
                            li_ModifiedPeptideRowCount = 0
                            lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide].keys.each do |ls_Description|
                                lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide][ls_Description].keys.each do |ls_Spot|
                                    li_ModifiedPeptideRowCount += 1
                                end
                            end
                            lb_ModifiedPeptideRow = true
                            lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide].keys.each do |ls_Description|
                                li_DescriptionRowCount = 0
                                lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide][ls_Description].keys.each do |ls_Spot|
                                    li_DescriptionRowCount += 1
                                end
                                lb_DescriptionRow = true
                                lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide][ls_Description].keys.each do |ls_Spot|
                                    ls_Mod = ls_ModifiedPeptide.dup
                                    ls_Mod.gsub!(/([a-z])/, "<b>\\1</b>")
                                    unless lb_FoundAny
                                        lk_Out.puts '<p>These peptides have been found with modifications.</p>'
                                        lk_Out.puts '<table>'
                                        lk_Out.puts '<thead>'
                                        lk_Out.puts '<tr><th>Peptide</th><th>Modified peptide</th><th>Description</th><th>Scan</th></tr>'
                                        lk_Out.puts '</thead>'
                                        lk_Out.puts '<tbody>'
                                        lb_FoundAny = true
                                    end
                                    lk_Out.puts "<tr>"
                                    if (lb_PeptideRow)
                                        lk_Out.puts "<td id='modified-peptide-#{ls_Peptide}' rowspan='#{li_PeptideRowCount}'>#{ls_Peptide}</td>"
                                        lb_PeptideRow = false
                                    end
                                    if (lb_ModifiedPeptideRow)
                                        lk_Out.puts "<td rowspan='#{li_ModifiedPeptideRowCount}'>#{ls_Mod.upcase}</td>"
                                        lb_ModifiedPeptideRow = false
                                    end
                                    if (lb_DescriptionRow)
                                        lk_Out.puts "<td rowspan='#{li_DescriptionRowCount}'>#{ls_Description}</td>"
                                        lb_DescriptionRow = false
                                    end
                                    lk_Out.puts "<td>#{lk_PeptideHash[ls_Peptide][:mods][ls_ModifiedPeptide][ls_Description][ls_Spot].sort { |a, b| String::natcmp(a, b)}.join(', ')}</td>"
                                    lk_Out.puts "</tr>"
                                end
                            end
                        end
                    end
                    if lb_FoundAny
                        lk_Out.puts '</tbody>'
                        lk_Out.puts '</table>'
                    else
                        lk_Out.puts '<p>No modified peptides have been found.</p>'
                    end
                end
                
                if @param[:writeAllIdentifiedPeptides]
                    lk_Out.puts "<h2 id='header-all-identified-peptides'>All identified peptides</h2>"
                    lk_Out.puts "<p>"
                    lk_Out.puts "The following list contains all peptides that have been identified, regardless of whether they appear in multiple proteins or not. The list is sorted by scan count."
                    lk_Out.puts "Peptides that have additionally been found by de novo prediction and GPF searching are <span class=\'gpf-confirm\'>highlighted</span>." unless lk_GpfPeptides.empty?
                    lk_Out.puts "</p>"
                    lk_Out.puts '<table>'
                    lk_Out.puts '<thead>'
                    lk_Out.puts '<tr><th>Scan count</th><th>Peptide</th><th>Proteins</th><th>Scan</th><th>E-value</th></tr>'
                    lk_Out.puts '</thead>'
                    lk_Out.puts '<tbody>'
                    lk_PeptideHash.keys.sort { |a, b| lk_PeptideHash[b][:scans].size <=> lk_PeptideHash[a][:scans].size }.each do |ls_Peptide|
                        li_ScanCount = lk_PeptideHash[ls_Peptide][:scans].size
                        ls_CellStyle = lk_PeptideHash[ls_Peptide][:found][:gpf]? ' class=\'gpf-confirm\'' : ''
                        lk_ScanInfo = lk_PeptideHash[ls_Peptide][:scans].sort do |a, b|
                            String::natcmp(a, b)
                        end
                        lk_Out.puts "<tr><td rowspan='#{li_ScanCount}'>#{li_ScanCount}</td><td rowspan='#{li_ScanCount}'><span#{ls_CellStyle}>#{ls_Peptide}</span> #{(!lk_PeptideHash[ls_Peptide][:mods].empty?) ? '<a href=\'#modified-peptide-' + ls_Peptide + '\' class=\'toggle\'>[mods]</span>' : ''}</td><td rowspan='#{li_ScanCount}'><ul>#{lk_PeptideHash[ls_Peptide][:proteins].keys.collect { |x| "<li>#{formatProtein(x)}</li>" }.join(' ')}</ul></td><td>#{lk_ScanInfo.first}</td><td>#{sprintf('%e', lk_ScanHash[lk_ScanInfo.first][:e])}</td></tr>"
                        (1...li_ScanCount).each do |i|
                            lk_Out.puts "<tr><td>#{lk_ScanInfo[i]}</td><td>#{sprintf('%e', lk_ScanHash[lk_ScanInfo[i]][:e])}</td></tr>"
                        end
                    end
                    lk_Out.puts '</tbody>'
                    lk_Out.puts '</table>'
                end
                
                lk_Out.puts '</body>'
                lk_Out.puts '</html>'
            end
        end
    end
end

script = WriteOmssaReport.new
