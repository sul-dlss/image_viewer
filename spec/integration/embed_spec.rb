require 'spec_helper'

#=begin

describe 'purl', type: :feature do
  before do
    @image_object = 'xm166kd3734'
    @file_object = 'wp335yr5649'
    @flipbook_object = 'yr183sf1341'
    @manifest_object = 'bb157hs6068'
    @embed_object = 'bf973rp9392'
    @incomplete_object = 'bb157hs6069'
    @unpublished_object = 'ab123cd4567'
    @legacy_object = 'ir:rs276tc2764'
    @no_mods_object = 'dh395xy5058'
    @nested_resources_object = 'dm907qj6498'
  end

  describe 'embeded viewer' do
    it 'should have the needed json embedded in a javascript variable' do
      # capybara wants a real html document, not a weird fragment. picky picky. use rspec.
      visit '/bf973rp9392/embed-js'
      # this is a crummy way to test for the presence of the data, but it is embedded as a javascript variable. Once it is a separate json path, this can be done in a better way
      expect(page.body).to include('var peImgInfo = [{"id":"bf973rp9392_00_0001","label":"Item 1","width":1740,"height":1675,"sequence":1,"rightsWorld":"true","rightsWorldRule":"","rightsStanford":"false","rightsStanfordRule":""}')
      expect(page.body.include?('var peStacksURL = "http://stacks-test.stanford.edu";')).to eq(true)
    end
    it 'should 404 if the item isnt an image object for /druid/embed-js' do
      visit "/#{@file_object}/embed-js"
      expect(page.status_code).to eq(404)
    end
    it 'should 404 if the item isnt an image object for /druid/embed-html-json' do
      visit "/#{@file_object}/embed-html-json"
      expect(page.status_code).to eq(404)
    end
    it 'should 404 if the item isnt an image object for /druid/embed' do
      visit "/#{@file_object}/embed"
      expect(page.status_code).to eq(404)
    end
    it 'should get the html-json data' do
      visit "/#{@embed_object}/embed-html-json"
      expect(page.body).to include '{"id":"bf973rp9392_00_0002","label":"Item 2","width":1752,"height":1687,"sequence":2,"rightsWorld":"true","rightsWorldRule":"","rightsStanford":"false","rightsStanfordRule":""}'
    end
    it 'should 404 for an unpublished object' do
      visit "/#{@unpublished_object}/embed-html-json"
      expect(page.status_code).to eq(404)
      # this is from 404.html....not sure why but thats how the app works
      expect(page).to have_content 'The page you were looking for doesn\'t exist.'
    end
    it 'should render the embed view' do
      visit "/#{@embed_object}/embed"
      expect(page.body).to include 'var peImgInfo = [{"id":"bf973rp9392_00_0001","label":"Item 1","width":1740,"height":1675,"sequence":1,"rightsWorld":"true","rightsWorldRule":"","rightsStanford":"false","rightsStanfordRule":""}'
      expect(page.body.include?('var peStacksURL = "http://stacks-test.stanford.edu";')).to eq(true)
    end
    it 'should 404 for an unpublished object' do
      visit "/#{@unpublished_object}/embed"
      expect(page.status_code).to eq(404)
      # this is from 404.html....not sure why but thats how the app works
      expect(page).to have_content 'The page you were looking for doesn\'t exist.'
    end
    it 'should error on invalid druids' do
      visit '/abcdefg/embed'
      expect(page.status_code).to eq(404)
    end
  end
end

#=end
