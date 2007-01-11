# 
#  svn_log_parser.rb
#  Subversion.tmbundle
#  
#  Usage:
#
# 	LogParser.parse_path(path) {|hash_for one_log_entry| ... }
# 	LogParser.parse(string_or_IO) {|hash_for one_log_entry| ... }
#
#  TODO: error reporting
#
#  Created by Chris Thomas on 2006-12-30.
#  Copyright 2006 Chris Thomas. All rights reserved.
# 

require 'rexml/document'
require 'time'
require 'uri'
require 'yaml'

require "#{ENV["TM_SUPPORT_PATH"]}/lib/plist"
require "#{ENV["TM_SUPPORT_PATH"]}/lib/dialog"
require "#{ENV["TM_SUPPORT_PATH"]}/lib/progress"
require "#{ENV["TM_SUPPORT_PATH"]}/lib/escape"

ListNib = File.dirname(__FILE__) + "/nibs/RevisionSelector.nib"

module Subversion
	
	def self.svn_cmd(args)
		result_text = %x{"#{ENV['TM_SVN']||'svn'}" #{args}}
		raise if $CHILD_STATUS != 0		
		result_text
	end
	
	def self.human_readable_mktemp(filename, rev)
		extname = File.extname(filename)
		filename = File.basename(filename)
		# TODO: Make sure the filename can fit in 255 characters, the limit on HFS+ volumes.
		
		"#{filename}-r#{rev}#{extname}"
	end
	
	def self.view_revision(path)
		
		# Get the desired revision number
		revision = choose_revision(path, "Choose a revision to view" )
		return if revision.nil?

		# Get the file at the desired revision
		log_data = ''
		TextMate.call_with_progress(:title => "R",
	          :summary => "Retrieving revision #{revision}…",
						:details => "#{File.basename(path)}") do
			
			temp_name = '/tmp/' + human_readable_mktemp(path, revision)
			svn_cmd("cat -r#{revision} #{e_sh(path)} > #{temp_name}")
			
			# Open the file in TextMate and then delete it when it's closed.
			%x{"#{ENV['TM_SUPPORT_PATH']}/bin/mate" -w #{e_sh(temp_name)}}
			File.delete(temp_name)
	  end
		
	end
	
	# on failure: returns nil
	def self.choose_revision(path, prompt)
		escaped_path = e_sh(path)
		
		# Get the server name
	  info = YAML::load(svn_cmd("info #{escaped_path}"))
		repository = info['Repository Root']
		uri = URI::parse(repository)

		# Display progress dialog
		log_data = ''
		TextMate.call_with_progress(:title => "Retrieving List of Revisions",
	          :summary => "Reading the log from “#{uri.host}”…",
						:details => "#{File.basename(path)}") do
				log_data = svn_cmd("log --xml #{escaped_path}")
	  end
		
		# Parse the log
		plist = []
		Subversion::LogParser.parse(log_data) do |hash|
			plist << hash
		end
		
		if plist.size == 0
			TextMate::Dialog.alert("No older revisions of file “#{path}” found", "There's only one revision of this file, and you already have it.")
		end
		
		# Show the log and ask for the revision number
		revision = 0
		TextMate::Dialog.dialog(ListNib, {'entries' => plist}) do |dialog|
			dialog.wait_for_input do |params|
				revision = params['returnArgument']
				false
			end
			dialog.close
		end
		
		# Return the revision number or nil
		revision = nil if revision == 0
		revision
	end
	
	# Streaming 'svn log --xml' output parser.
	class LogParser
		
		# path may be a Subversion working copy path or a repository URL
		def LogParser.parse_path(path, &block)
			path = File.expand_path(path)
			log_cmd = %Q{"#{ENV['TM_SVN']||svn}" log --xml "#{path}"}

			IO.popen(log_cmd, "r") do |io|
				LogParser.parse(io) do |hash|
					block.call(hash)
				end
			end # IO.popen
		end
		
		# source may be a string or an IO subclass
		def LogParser.parse(source, &block)
			listener = LogParser.new(&block)
			
			# TODO: remove and report any text prior to the XML data
			REXML::Document.parse_stream(source, listener)
		end

		# This listener makes no attempt to validate according to schema.
		# The SVN log node names are unique and nonrecursive,
		# so this shouldn't be an issue. But it would be nice as a sanity check.
		def initialize(&block)
			@callback_block = block
		end
	
		def xmldecl(*ignored)
		end
	
		def tag_start(name, attributes)
			case name
			when 'logentry'
				revision = attributes['revision']
				@current_log = {'rev' => revision.to_i}
			end
		end

		def tag_end(name)
			case name
			when 'author','msg'
				@current_log[name] = @text
			when 'date'
				@current_log[name] = Time.xmlschema(@text)
			when 'logentry'
				@callback_block.call(@current_log)
			end
		end
	
		def text(text)
			@text = text
		end

	end # class LogParser
end # module Subversion

if __FILE__ == $0
	
#	test_path = "~/Library/Application Support/TextMate/Bundles/Ada.tmbundle"
	test_path = "~/TestRepo/TestFiles"
	Subversion::LogParser.parse_path(test_path) do |hash|
		puts hash.inspect
	end
	
	# plist
	plist = []
	Subversion::LogParser.parse_path(test_path) do |hash|
		plist << hash
	end
	puts plist.to_plist
	
end

