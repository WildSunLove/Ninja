#!/usr/bin/env ruby

require 'optparse'
require 'csv'

options={}
OptionParser.new do |opts|
  opts.banner = "Usage: ./event-stream.rb [options]"

  opts.on("--number [NUMBER_REPOS]", Integer, "Query the top N repositories(default 100)") do |n|
    options[:n]=n
  end

  opts.on("-d", "Don't update top_repos list(Saves some data if it already exists") do
    options[:d]=true
  end

  opts.on("-v", "Verbose") do
    options[:v]=true
  end

  opts.on_tail("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

def update_top(n)
  query = <<-EOF
SELECT repository_url, MAX(repository_forks) as num_forks
FROM [githubarchive:github.timeline]
WHERE repository_name!='' AND repository_owner!=''
GROUP BY repository_url
ORDER BY num_forks DESC
LIMIT #{n};
  EOF
  puts %x{bq rm -f mygithubarchives.top_#{n}_repos}
  puts "Beginning top_repos query"
  puts %x{bq query --destination_table=mygithubarchives.top_#{n}_repos "#{query}"}
  puts "Done"
end

def get_stream(n)
  query = <<-EOF
SELECT T.repository_url AS id, M.num_forks AS forks, T.created_at AS timestamp, T.type AS event
FROM githubarchive:github.timeline AS T
JOIN mygithubarchives.top_#{n}_repos AS M ON T.repository_url=M.repository_url
ORDER BY forks DESC, id ASC, timestamp ASC;
  EOF
  puts "Beginning event_stream query"
  x = CSV.parse(`bq --format csv -q query --max_rows 99999999 "#{query}"`).collect do |a|
    begin
      a[0..0]+a[2..-1]
    rescue
      puts "ERROR"
      p a
      exit
    end
  end
  File.open("event-stream-#{n}.csv", 'w'){|f| f.puts `bq --format csv -q query --max_rows 99999999 "#{query}"`}
end

num = options[:n] || 100
update_top(num) unless options[:d]
get_stream(num)