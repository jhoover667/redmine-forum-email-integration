# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require File.dirname(__FILE__) + '/../test_helper'

class RepositoryTest < Test::Unit::TestCase
  fixtures :projects,
           :trackers,
           :projects_trackers,
           :repositories,
           :issues,
           :issue_statuses,
           :changesets,
           :changes,
           :users,
           :enumerations
  
  def setup
    @repository = Project.find(1).repository
  end
  
  def test_create
    repository = Repository::Subversion.new(:project => Project.find(3))
    assert !repository.save
  
    repository.url = "svn://localhost"
    assert repository.save
    repository.reload
    
    project = Project.find(3)
    assert_equal repository, project.repository
  end
  
  def test_should_not_create_with_disabled_scm
    # disable Subversion
    Setting.enabled_scm = ['Darcs', 'Git']
    repository = Repository::Subversion.new(:project => Project.find(3), :url => "svn://localhost")
    assert !repository.save
    assert_equal :activerecord_error_invalid, repository.errors.on(:type)
    # re-enable Subversion for following tests
    Setting.delete_all
  end
  
  def test_scan_changesets_for_issue_ids
    # choosing a status to apply to fix issues
    Setting.commit_fix_status_id = IssueStatus.find(:first, :conditions => ["is_closed = ?", true]).id
    Setting.commit_fix_done_ratio = "90"
    Setting.commit_ref_keywords = 'refs , references, IssueID'
    Setting.commit_fix_keywords = 'fixes , closes'
    Setting.default_language = 'en'
    ActionMailer::Base.deliveries.clear
    
    # make sure issue 1 is not already closed
    fixed_issue = Issue.find(1)
    assert !fixed_issue.status.is_closed?
    old_status = fixed_issue.status
        
    Repository.scan_changesets_for_issue_ids
    assert_equal [101, 102], Issue.find(3).changeset_ids
    
    # fixed issues
    fixed_issue.reload
    assert fixed_issue.status.is_closed?
    assert_equal 90, fixed_issue.done_ratio
    assert_equal [101], fixed_issue.changeset_ids
    
    # issue change
    journal = fixed_issue.journals.find(:first, :order => 'created_on desc')
    assert_equal User.find_by_login('dlopper'), journal.user
    assert_equal 'Applied in changeset r2.', journal.notes
    
    # 2 email notifications
    assert_equal 2, ActionMailer::Base.deliveries.size
    mail = ActionMailer::Base.deliveries.first
    assert_kind_of TMail::Mail, mail
    assert mail.subject.starts_with?("[#{fixed_issue.project.name} - #{fixed_issue.tracker.name} ##{fixed_issue.id}]")
    assert mail.body.include?("Status changed from #{old_status} to #{fixed_issue.status}")
    
    # ignoring commits referencing an issue of another project
    assert_equal [], Issue.find(4).changesets
  end
  
  def test_for_changeset_comments_strip
    repository = Repository::Mercurial.create( :project => Project.find( 4 ), :url => '/foo/bar/baz' )
    comment = <<-COMMENT
    This is a loooooooooooooooooooooooooooong comment                                                   
                                                                                                       
                                                                                            
    COMMENT
    changeset = Changeset.new(
      :comments => comment, :commit_date => Time.now, :revision => 0, :scmid => 'f39b7922fb3c',
      :committer => 'foo <foo@example.com>', :committed_on => Time.now, :repository => repository )
    assert( changeset.save )
    assert_not_equal( comment, changeset.comments )
    assert_equal( 'This is a loooooooooooooooooooooooooooong comment', changeset.comments )
  end
  
  def test_for_urls_strip
    repository = Repository::Cvs.create(:project => Project.find(4), :url => ' :pserver:login:password@host:/path/to/the/repository',
                                                                     :root_url => 'foo  ')
    assert repository.save
    repository.reload
    assert_equal ':pserver:login:password@host:/path/to/the/repository', repository.url
    assert_equal 'foo', repository.root_url
  end
end
