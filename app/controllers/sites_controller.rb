class SitesController < ApplicationController
  before_filter :authenticate_user!

  expose(:sites)
  expose(:site)

  def index
    render :json => collection.root_sites.offset(params[:offset]).limit(params[:limit])
  end

  def create
    render :json => collection.sites.create(params[:site])
  end

  def update
    site.update_attributes params[:site]
    render :json => site
  end

  def root_sites
    render :json => site.sites.where(:parent_id => site.id).offset(params[:offset]).limit(params[:limit])
  end

  def search
    n, s, e, w = params.fetch_many(:n, :s, :e, :w).map &:to_f
    zoom = params[:z].to_i
    width, height = Clusterer.cell_size_for zoom

    search = Search.new params[:collection_ids]
    search.bounds = {:n => n + height, :s => s - height, :e => e + width, :w => w - width} if zoom > 2
    render :json => cluster(search.sites)
  end

  private

  def cluster(sites)
    clusterer = Clusterer.new params[:z]
    sites.each { |site| clusterer.add site }
    clusterer.clusters
  end
end
