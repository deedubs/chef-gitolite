require 'rubygems'
require 'tinder'
require 'uri'

class GitCampfireNotification

  def initialize(options = {})
    # campfire_config keys: subdomain, use_ssl, email, password, room
    @campfire_config = options[:campfire_config]

    # git keys: ref_name, old_revision, new_revision
    @ref_name     = options[:ref_name]
    @old_revision = options[:old_revision]
    @new_revision = options[:new_revision]

    @old_revision_type = `git cat-file -t #{@old_revision} 2> /dev/null`.strip
    @new_revision_type = `git cat-file -t #{@new_revision} 2> /dev/null`.strip

    if ref_name_type.include?("branch")
      send "#{change_type}_branch"
    elsif ref_name_type.include?("tag")
      send "create_#{ref_name_type.gsub(' ', '_')}"
    end
  end


  private

  def campfire_room
    if @campfire.nil?
      @campfire = Tinder::Campfire.new(@campfire_config[:subdomain], :token => @campfire_config[:token])
    end
    @campfire_room ||= @campfire.find_room_by_name(@campfire_config[:room])
  end

  def project_name
    project_name = File.expand_path(`git rev-parse --git-dir 2>/dev/null`.strip).split("/").last
    if project_name == ".git"
      project_name = File.basename(Dir.pwd)
    end
    project_name.sub(/\.git$/, "")
  end

  def change_type
    if @old_revision =~ /^0*$/
      :create
    elsif @new_revision =~ /^0*$/
      :delete
    else
      :update
    end
  end

  def short_ref_name
    @ref_name.match(%r{^refs/(?:tags|heads|remotes)/(.+)$})[1]
  end

  def ref_name_type
    rev_type = (change_type == :delete) ? @old_revision_type : @new_revision_type
    ref_name_types = {%w(tags    commit) => "lightweight tag",
                      %w(tags    tag)    => "annotated tag",
                      %w(heads   commit) => "branch",
                      %w(remotes commit) => "tracking branch"}
    @ref_name.match(%r{^refs/(tags|heads|remotes)/.+$})
    ref_name_types[[$1, rev_type]]
  end


  def new_commits
    revision_range = (change_type == :create) ? @new_revision : "#{@old_revision}..#{@new_revision}"

    other_branches = `git for-each-ref --format='%(refname)' refs/heads/ | grep -F -v #{@ref_name}`
    other_branches.gsub!("\n", " ") # We don't want newlines in the arguments for git rev-parse
    sentinel = "=-=-*-*-" * 10
    raw_commits = `git rev-parse --not #{other_branches} | git rev-list --reverse --pretty=format:'%cn%n%s%n%n%b#{sentinel}' --stdin #{revision_range}`.split(sentinel)
    raw_commits.pop # last is empty because there's an ending sentinel

    raw_commits.inject([]) { |commits, raw_commit|
      lines = raw_commit.strip.split("\n")
      commits << {:revision  => lines[0].sub(/^commit /, ""),
                  :committer => lines[1],
                  :message   => lines[2..-1].join("\n")}
    }
  end

  def speak_new_commits
    new_commits.each do |c|
      say "#{c[:committer]} just committed #{c[:revision]}"
      say "[#{project_name}] #{c[:message]}", :paste
    end
  end


  def update_branch
    if `git rev-list #{@new_revision}..#{@old_revision}`.empty?
      update_type = :fast_foward
    elsif @new_revision == `git merge-base #{@old_revision} #{@new_revision}`.strip
      update_type = :rewind
      say "The remote #{ref_name_type} #{project_name}/#{short_ref_name} was just rewound to a previous commit"
    else
      update_type = :force
      say "The remote #{ref_name_type} #{project_name}/#{short_ref_name} was just force-updated"
    end

    unless update_type == :rewind
      speak_new_commits
    end
  end

  def create_branch
    say "A new remote #{ref_name_type} was just pushed to #{project_name}/#{short_ref_name}:"
    speak_new_commits
  end

  def delete_branch
    say "The remote #{ref_name_type} #{project_name}/#{short_ref_name} was just deleted"
  end

  def create_lightweight_tag
    sha = `git rev-parse #{short_ref_name}`
    say "A new lightweight tag was just pushed; #{project_name}/#{short_ref_name} is #{sha[0...8]}"
  end

  def create_annotated_tag
    raw_commit = `git show --pretty=medium #{short_ref_name}`
    tagger     = raw_commit[/\nTagger: (.+) <[^>]+>\n/, 1]
    annotation = raw_commit[/\n\n(.+)\n\ncommit [0-9a-f]{40}\n/, 1]
    sha        = `git rev-parse #{short_ref_name}`

    say "#{tagger} just pushed a new annotated tag, #{project_name}/#{short_ref_name} points to #{sha[0...8]}:"
    say "[#{project_name}] #{annotation}", :paste
  end

  def delete_tag
    say "The #{ref_name_type} #{project_name}/#{short_ref_name} was just deleted"
  end

  def say(what, paste = false)
    if ENV["USE_STDOUT"]
      paste ? $stdout.puts("[campfire p] #{what}") : $stdout.puts("[campfire] #{what}")
    else
      paste ? campfire_room.paste(what) : campfire_room.speak(what)
    end
  end

end

