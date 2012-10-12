require 'irb'

module IRB
  def self.start_session(binding)
    IRB.setup(nil)

    workspace = WorkSpace.new(binding)

    if @CONF[:SCRIPT]
      irb = Irb.new(workspace, @CONF[:SCRIPT])
    else
      irb = Irb.new(workspace)
    end

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context

    trap("SIGINT") do
      irb.signal_handle
    end

    catch(:IRB_EXIT) do
      irb.eval_input
    end
  end
end

require 'jnlp'

# new_jnlp = Jnlp::Jnlp.new("http://jnlp.concord.org/dev3/org/concord/maven-jnlp/itsisu-otrunk/itsisu-otrunk-0.1.0-20120203.190751.jnlp")
new_jnlp = Jnlp::Jnlp.new("itsisu-otrunk-0.1.0-20120203.190751.jnlp")
old_jnlp = Jnlp::Jnlp.new("http://itsisu.portal.concord.org/activities/17.jnlp?teacher_mode=true")

new_jars = new_jnlp.jars
old_jars = old_jnlp.jars

new_jar_map = {}
new_jars.each{|nj| new_jar_map[nj] = old_jars.find{|oj| oj.href == nj.href}}

diff_jars_map = {}
new_jar_map.each{|nj,oj|
  if oj.nil? || nj.version_str != oj.version_str
    diff_jars_map[nj] = oj
  end
}

diff_jars_map.each{|nj,oj|
  next if oj.nil?
  nj.resource['version'] = oj.version_str
}

# IRB.start_session(Kernel.binding)

new_jnlp.write_jnlp :jnlp => {}

exit(0)

`mkdir -p cache`
diff_jars_map.each{|nj,oj|
  nj.cache_resource('cache', {:skip_signature_verfication => true, :verbose => true})
  if oj
    oj.cache_resource('cache', {:skip_signature_verfication => true, :verbose => true})
  end
}

def print_differences(map)
  map.each{|nj,oj|
    if oj
      puts "  updated\t#{nj.href}\t#{nj.version_str}\t#{oj.version_str}"
    else
      puts "  new\t#{nj.href}\t#{nj.version_str}"
    end
  }
end

puts "Based on the versions their have been the following changes:"
print_differences diff_jars_map

`mkdir -p unzipped/old`
`mkdir -p unzipped/new`

# pair = diff_jars_map.first
#
# `rm -r unzipped/old/*`
# `rm -r unzipped/new/*`
# `unzip -d unzipped/old #{pair[1].local_path} -x META-INF/* `
# `unzip -d unzipped/new #{pair[0].local_path} -x META-INF/* `

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
  end
}

puts "Based on the actual file content"
print_differences diff_content_jars_map

`mkdir -p tmp`

source_changes_map = {}
diff_content_jars_map.each{|nj,oj|
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

diff_content_jars_map.each{|nj,oj|
  if oj
    puts "  updated\t#{nj.href}\t#{nj.version_str}\t#{oj.version_str}\t#{source_changes_map[nj]}"
  else
    puts "  new\t#{nj.href}\t#{nj.version_str}"
  end
}


# new_jnlp.jars.each{|j| puts j.href + j.version_str }; nil

# IRB.start_session(Kernel.binding)


