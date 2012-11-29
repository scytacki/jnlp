#!/usr/bin/env ruby

require 'trollop'
require_relative 'lib/jnlp'

$options = Trollop::options do
  opt :sizes, "Show sizes of difference"
  opt :classes, "Expand jars and compare classes"
  opt :show_content_diff, "Show which classes differ"
  opt :source_changes, "Look for pom inside of jar and lookup date of last source code change"
end

class JarPair
  attr_accessor :new_jar
  attr_accessor :old_jar
  attr_accessor :content_differences

  def diff_versions?
    old_jar && new_jar && new_jar.version_str != old_jar.version_str
  end

  def compaired_content?
    @compaired_content
  end

  def diff_contents?
    return false unless diff_versions?
    if compaired_content?
      return content_differences != ""
    end

    `rm -rf unzipped/old/*`
    `rm -rf unzipped/new/*`
    `unzip -d unzipped/old #{old_jar.local_path} -x META-INF/*`
    `unzip -d unzipped/new #{new_jar.local_path} -x META-INF/*`
    differences = `cd unzipped; diff -r old new`
    if $?.to_i == 0
      # the class files match in these jars
      self.content_differences = ""
    else
      self.content_differences = differences
    end
    @compaired_content = true

    return content_differences != ""
  end

  def different?
    if options[:classes]
      diff_contents?
    else
      diff_versions?
    end
  end

  def source_change_date
    return @source_change_date if @source_change_date

    `rm -f tmp/*`
    `unzip -j -d tmp #{nj.local_path} *pom.xml`
    `cd tmp; mvn help:effective-pom -Doutput=effective-pom.xml`
    # pull out the project/scm/connection url from the effective-pom.xml
    scm_connection = `xpath tmp/effective-pom.xml "/project/scm/connection/text()"  2> /dev/null`
    if scm_connection =~ /scm:svn:(.*)/
      svn_info = `svn info #{$1}`
      @source_change_date = svn_info.scan(/Last Changed Date:(.*)/)[0][0]
    else
      @source_change_date = "unknown date"
    end
  end

  def new_jar_size
    return @new_jar_size if @new_jar_size
    return 0 if new_jar.nil?

    begin
      url = URI.parse(new_jar.url_pack_gz)
      connection = Net::HTTP.new(url.host, url.port)
      response = connection.request_head(url.path)
      @new_jar_size = response.content_length
    rescue
      puts "failed to get jar #{url.path.to_s}"
    end

    @new_jar_size
  end

  def href
    return new_jar.href if new_jar
    return old_jar.href
  end

  def print_diff
    items = []
    if new_jar.nil?
      items << "remove"
    elsif old_jar.nil?
      items << "add   "
    elsif diff_versions?
      # we still print differences even if the contents are the same
      items << "change"
    else
      # no change
      return
    end

    if $options[:classes]
      # add a flag to indicate that only the versions are different
      items << ((diff_versions? && !diff_contents?) ? "v" : " ")
    end
    items << "#{href}"
    if $options[:sizes] && new_jar
      items << "#{new_jar_size} bytes"
    end

    if old_jar
      items << old_jar.version_str
    end

    if new_jar
      items << new_jar.version_str
    end

    if $options[:source_changes] && different?
      # only figure out the source change date if the jars are different because it is expensive
      # and here we use the different? method so if the content has been compaired we only care about
      # jars with different content
      items << "#{source_changes_date}"
    end

    puts items.join("\t")

    if $options[:show_content_diff] && diff_contents?
      puts content_differences
    end
  end
end

puts "comparing #{ARGV[0]} to #{ARGV[1]}"
old_jnlp = Jnlp::Jnlp.new(ARGV[0])
new_jnlp = Jnlp::Jnlp.new(ARGV[1])

new_jars = new_jnlp.jars
old_jars = old_jnlp.jars

pairs = new_jars.map{|nj|
  pair = JarPair.new
  pair.new_jar = nj
  pair.old_jar = old_jars.find{|oj| oj.href == nj.href}
  pair
}

# add jars that are only in the old_jnlp
old_jars.each{|oj|
  unless pairs.find{|pair| pair.old_jar == oj}
    pair = JarPair.new
    pair.old_jar = oj
    pairs << pair
  end
}

diff_versions = pairs.select{|pair| pair.diff_versions?}

`mkdir -p unzipped/old`
`mkdir -p unzipped/new`
`mkdir -p cache`

# prefetching like this makes it clear that there are 2 phases of the compairison
if $options[:classes] || $options[:source_changes]
  diff_versions.each{|pair|
    pair.new_jar.cache_resource('cache', {:skip_signature_verfication => true, :verbose => true})
    pair.old_jar.cache_resource('cache', {:skip_signature_verfication => true, :verbose => true})
  }
end

def print_summary(name, pairs_to_summarize)
  puts name
  pairs_to_summarize.each{|pair| pair.print_diff }
  if $options[:sizes]
    total_size = 0
    pairs_to_summarize.each{|pair| total_size += pair.new_jar_size }
    puts "Size of added or changed jars #{total_size} bytes"
  end
  count = pairs_to_summarize.select{|pair| pair.new_jar}.size
  puts "Number of added or changed jars #{count}"
end

# need a list of pairs that includes removed, added, and changed jars
based_on_version = pairs.select{|pair| pair.new_jar.nil? || pair.old_jar.nil? || pair.diff_versions?}
print_summary("Differences based on version", based_on_version)

if $options[:classes]
  puts "('v' means that only the versions are different but the content is the same)"
  puts ""
  based_on_content = pairs.select{|pair| pair.new_jar.nil? || pair.old_jar.nil? || pair.diff_contents?}
  print_summary("Differences based on contents", based_on_content)
end


