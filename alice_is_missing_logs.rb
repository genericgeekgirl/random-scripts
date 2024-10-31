# Script to process chat logs from playing Alice is Missing on Discord
# Adri - Oct 30 2024

require 'json'

logs = {}

user_channels = {}

GROUP_CHAT = "group_chat"
OOC_CHAT = "setup-and-debrief"

player_characters = {}

filenames = Dir.entries(".")
filenames.each do | filename |
  next unless filename.include?(".json")
  channel = filename.gsub(/_page_\d.json/, "")
  File.readlines(filename, chomp: true).each do | json_line |
    lines = JSON.parse(json_line)
    lines.each do | line |
      user = line["userName"]
      user_channels[user] ||= []
      user_channels[user] |= [channel] unless [GROUP_CHAT, OOC_CHAT].include?(channel)
      timestamp = line["timestamp"]
      logs[timestamp] ||= []
      logs[timestamp] << { channel: channel, user: user, text: line["content"] }
    end
  end
end

user_channels.each do | user, channels |
  if channels.empty?
    character = "facilitator"
  else
    participants = channels.map { | channel | channel.split("_") }.flatten
    occurrences = participants.inject(Hash.new(0)){ |h, x| h[x] += 1; h }
    character = (occurrences.sort_by { | k, v | -v }).first[0]
  end
  player_characters[user] = character
end

puts player_characters
puts logs.keys.first

output_file = "transcript.txt"

File.open(output_file, "w") {}

Hash[logs.sort].each do | timestamp, lines |
  lines.each do | line |
    author = player_characters[line[:user]]
    channel = line[:channel]
    text = line[:text]
    
    if channel == GROUP_CHAT
      recipient = "group"
    elsif channel != OOC_CHAT
      recipient = (channel.split("_") - [author]).first
    end
    
    if recipient.nil?
      log_line = "[#{line[:channel]}] #{author}: \"#{text}\""
    else
      log_line = "#{author} (to #{recipient}): \"#{text}\""
    end
    
    File.write(output_file, log_line+"\n",  mode: 'a')
  end    
end
