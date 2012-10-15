#!/usr/bin/env ruby

require 'trollop'
require_relative 'lib/jnlp'

options = Trollop::options do
  opt :sizes, "Show sizes of difference"
  opt :classes, "Expand jars and compare classes"
  opt :show_content_diff, "Show which classes differ"
  opt :source_changes, "Look for pom inside of jar and lookup date of last source code change"
end

def print_differences(map, sizes, content_differences, options)
end

puts "comparing #{ARGV[0]} to #{ARGV[1]}"
old_jnlp = Jnlp::Jnlp.new(ARGV[0])
new_jnlp = Jnlp::Jnlp.new(ARGV[1])

new_jars = new_jnlp.jars
old_jars = old_jnlp.jars

new_jar_map = {}
new_jars.each{|nj|
  new_jar_map[nj] = old_jars.find{|oj| oj.href == nj.href}
}

diff_jars_map = {}
new_jar_map.each{|nj,oj|
  if oj.nil? || nj.version_str != oj.version_str
    diff_jars_map[nj] = oj
  end
}

if options[:classes] || options[:source_changes]
  `mkdir -p cache`
  diff_jars_map.each{|nj,oj|
    nj.cache_resource('cache', {:skip_signature_verfication => true, :verbose => true})
    if oj
      oj.cache_resource('cache', {:skip_signature_verfication => true, :verbose => true})
    end
  }
end

if options[:classes]
  `mkdir -p unzipped/old`
  `mkdir -p unzipped/new`

  content_differences = {}
  diff_content_jars_map = {}
  diff_jars_map.each{|nj,oj|
    if oj.nil?
      diff_content_jars_map[nj] = nil
      next
    end

    `rm -rf unzipped/old/*`
    `rm -rf unzipped/new/*`
    `unzip -d unzipped/old #{oj.local_path} -x META-INF/*`
    `unzip -d unzipped/new #{nj.local_path} -x META-INF/*`
    differences = `cd unzipped; diff -r old new`
    if $?.to_i == 0
      # the class files match in these jars
    else
      diff_content_jars_map[nj] = oj
      content_differences[nj] = differences
    end
  }

  puts "The follow jars have different versions but their classes are identical"
  diff_jars_map.each{|nj,oj|
    next if oj.nil?
    puts "  #{nj.href}" if !diff_content_jars_map[nj]
  }

  diff_jars = diff_content_jars_map
end

sizes = {}
if options[:sizes]
  total = 0
  diff_jars_map.each{|nj,oj|
  	begin
  		url = URI.parse(nj.url_pack_gz)
  		connection = Net::HTTP.new(url.host, url.port)
  		response = connection.request_head(url.path)
  		sizes[nj] = response.content_length
  		total += response.content_length
  	rescue
  		puts "failed to get jar #{url.path.to_s}"
  	end
  }
  puts "Total update size: #{total} bytes"
end

source_changes_map = {}
if options[:source_changes]
  `mkdir -p tmp`

  diff_jars_map.each{|nj,oj|
    if oj.nil?
      source_changes_map[nj] = "no point in checking"
      next
    end

    `rm -f tmp/*`
    `unzip -j -d tmp #{nj.local_path} *pom.xml`
    `cd tmp; mvn help:effective-pom -Doutput=effective-pom.xml`
    # pull out the project/scm/connection url from the effective-pom.xml
    scm_connection = `xpath tmp/effective-pom.xml "/project/scm/connection/text()"  2> /dev/null`
    if scm_connection =~ /scm:svn:(.*)/
      svn_info = `svn info #{$1}`
      source_changes_map[nj] = svn_info.scan(/Last Changed Date:(.*)/)[0][0]
    end
  }
end


puts "Differences"
diff_jars_map.each{|nj,oj|
  size = sizes[nj] ? "\t#{sizes[nj]} bytes" : ""
  source_change = source_changes_map[nj] ? "\t#{source_changes_map[nj]}" : ""
  if oj
    puts "  updated  #{nj.href}#{size}\t#{nj.version_str}\t#{oj.version_str}#{source_change}"
    if options[:show_content_diff] && differences = content_differences[nj]
    	puts differences
    end
  else
    puts "  new      #{nj.href}#{size}\t#{nj.version_str}"
  end
}

puts "Number of jars: #{diff_jars_map.size}"
