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

require 'diff'

class WikiController < ApplicationController
  layout 'base'
  before_filter :find_wiki, :authorize
  
  verify :method => :post, :only => [:destroy, :destroy_attachment, :protect], :redirect_to => { :action => :index }

  helper :attachments
  include AttachmentsHelper   
  
  # display a page (in editing mode if it doesn't exist)
  def index
    page_title = params[:page]
    @page = @wiki.find_or_new_page(page_title)
    if @page.new_record?
      if User.current.allowed_to?(:edit_wiki_pages, @project)
        edit
        render :action => 'edit'
      else
        render_404
      end
      return
    end
    @content = @page.content_for_version(params[:version])
    if params[:export] == 'html'
      export = render_to_string :action => 'export', :layout => false
      send_data(export, :type => 'text/html', :filename => "#{@page.title}.html")
      return
    elsif params[:export] == 'txt'
      send_data(@content.text, :type => 'text/plain', :filename => "#{@page.title}.txt")
      return
    end
	@editable = editable?
    render :action => 'show'
  end
  
  # edit an existing page or a new one
  def edit
    @page = @wiki.find_or_new_page(params[:page])    
    return render_403 unless editable?
    @page.content = WikiContent.new(:page => @page) if @page.new_record?
    
    @content = @page.content_for_version(params[:version])
    @content.text = "h1. #{@page.pretty_title}" if @content.text.blank?
    # don't keep previous comment
    @content.comments = nil
    if request.post?      
      if !@page.new_record? && @content.text == params[:content][:text]
        # don't save if text wasn't changed
        redirect_to :action => 'index', :id => @project, :page => @page.title
        return
      end
      #@content.text = params[:content][:text]
      #@content.comments = params[:content][:comments]
      @content.attributes = params[:content]
      @content.author = User.current
      # if page is new @page.save will also save content, but not if page isn't a new record
      if (@page.new_record? ? @page.save : @content.save)
        redirect_to :action => 'index', :id => @project, :page => @page.title
      end
    end
  rescue ActiveRecord::StaleObjectError
    # Optimistic locking exception
    flash[:error] = l(:notice_locking_conflict)
  end
  
  # rename a page
  def rename
    @page = @wiki.find_page(params[:page])
	return render_403 unless editable?
    @page.redirect_existing_links = true
    # used to display the *original* title if some AR validation errors occur
    @original_title = @page.pretty_title
    if request.post? && @page.update_attributes(params[:wiki_page])
      flash[:notice] = l(:notice_successful_update)
      redirect_to :action => 'index', :id => @project, :page => @page.title
    end
  end
  
  def protect
    page = @wiki.find_page(params[:page])
    page.update_attribute :protected, params[:protected]
    redirect_to :action => 'index', :id => @project, :page => page.title
  end

  # show page history
  def history
    @page = @wiki.find_page(params[:page])
    
    @version_count = @page.content.versions.count
    @version_pages = Paginator.new self, @version_count, per_page_option, params['p']
    # don't load text    
    @versions = @page.content.versions.find :all, 
                                            :select => "id, author_id, comments, updated_on, version",
                                            :order => 'version DESC',
                                            :limit  =>  @version_pages.items_per_page + 1,
                                            :offset =>  @version_pages.current.offset

    render :layout => false if request.xhr?
  end
  
  def diff
    @page = @wiki.find_page(params[:page])
    @diff = @page.diff(params[:version], params[:version_from])
    render_404 unless @diff
  end
  
  def annotate
    @page = @wiki.find_page(params[:page])
    @annotate = @page.annotate(params[:version])
  end
  
  # remove a wiki page and its history
  def destroy
    @page = @wiki.find_page(params[:page])
	return render_403 unless editable?
    @page.destroy if @page
    redirect_to :action => 'special', :id => @project, :page => 'Page_index'
  end

  # display special pages
  def special
    page_title = params[:page].downcase
    case page_title
    # show pages index, sorted by title
    when 'page_index', 'date_index'
      # eager load information about last updates, without loading text
      @pages = @wiki.pages.find :all, :select => "#{WikiPage.table_name}.*, #{WikiContent.table_name}.updated_on",
                                      :joins => "LEFT JOIN #{WikiContent.table_name} ON #{WikiContent.table_name}.page_id = #{WikiPage.table_name}.id",
                                      :order => 'title'
      @pages_by_date = @pages.group_by {|p| p.updated_on.to_date}
    # export wiki to a single html file
    when 'export'
      @pages = @wiki.pages.find :all, :order => 'title'
      export = render_to_string :action => 'export_multiple', :layout => false
      send_data(export, :type => 'text/html', :filename => "wiki.html")
      return      
    else
      # requested special page doesn't exist, redirect to default page
      redirect_to :action => 'index', :id => @project, :page => nil and return
    end
    render :action => "special_#{page_title}"
  end
  
  def preview
    page = @wiki.find_page(params[:page])
    # page is nil when previewing a new page
    return render_403 unless page.nil? || editable?(page)
    @attachements = page.attachments if page
    @text = params[:content][:text]
    render :partial => 'common/preview'
  end

  def add_attachment
    @page = @wiki.find_page(params[:page])
    return render_403 unless editable?
    attach_files(@page, params[:attachments])
    redirect_to :action => 'index', :page => @page.title
  end

  def destroy_attachment
    @page = @wiki.find_page(params[:page])
    return render_403 unless editable?
    @page.attachments.find(params[:attachment_id]).destroy
    redirect_to :action => 'index', :page => @page.title
  end

private
  
  def find_wiki
    @project = Project.find(params[:id])
    @wiki = @project.wiki
    render_404 unless @wiki
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  # Returns true if the current user is allowed to edit the page, otherwise false
  def editable?(page = @page)
    page.editable_by?(User.current)
  end
end
