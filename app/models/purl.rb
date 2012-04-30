require 'nokogiri'

require "lib/purl/util"
require "htmlentities"

class Purl
  
  include PurlUtils
  @@coder = HTMLEntities.new
  
  DEFERRED_TEMPLATE = %{def %1$s; extract_metadata unless @extracted; instance_variable_get("@%1$s"); end}
  def self.attr_deferred(*args)
    args.each { |a| eval(DEFERRED_TEMPLATE % a) }
  end

  attr_accessor :pid
  attr_accessor :public_xml
  attr_accessor :mods_xml
  attr_accessor :flipbook_json 
 
  attr_deferred :titles, :authors, :source, :date, :relation, :description, :contributors, :repository, :collection, :location # dc
  attr_deferred :degreeconfyr, :cclicense, :cclicensetype, :cclicense_symbol                     # properties
  attr_deferred :catalog_key                                                                     # identity
  attr_deferred :read_group, :embargo_release_date, :copyright_stmt, :use_and_reproduction_stmt  # rights
  attr_deferred :deliverable_files, :type                                                        # content
  attr_deferred :reading_order, :page_start                                                      # flipbook specific

  NAMESPACES = {     
    'oai_dc' => "http://www.openarchives.org/OAI/2.0/oai_dc/", 
    'dc' => 'http://purl.org/dc/elements/1.1/', 
    'dcterms' => 'http://purl.org/dc/terms/'
  }

  # Checks if the pair tree directory exists in the document cache for a given druid
  #
  def Purl.find(id)    
    purl = nil
    pair_tree = Purl.create_pair_tree(id)
    
    unless pair_tree.nil?
      file_path = File.join(DOCUMENT_CACHE_ROOT, pair_tree)
      purl = Purl.new(id) if File.exists?(file_path)
    end
    
    purl
  end
  
  # Returns the pair tree directory for a given, valid druid
  #
  def Purl.create_pair_tree(pid)
    pair_tree = nil 
    
    if pid =~ /^([a-z]{2})(\d{3})([a-z]{2})(\d{4})$/
      pair_tree = File.join($1, $2, $3, $4)
    end
    
    pair_tree
  end

  # initializes the object with metadata and service streams
  #
  def initialize(id)
    @pid = id
    @public_xml    = get_metadata('public')
    @mods_xml      = get_metadata('mods')
    @flipbook_json = get_flipbook_json
    @extracted     = false
  end
  
  def extract_metadata
    doc = ng_xml('dc','identityMetadata','contentMetadata','rightsMetadata','properties')
    
    # DC Metadata
    dc = doc.root.at_xpath('*[local-name() = "dc"]', NAMESPACES)
    unless dc.nil?
      @titles       = @@coder.decode(dc.xpath('dc:title/text()|dcterms:title/text()', NAMESPACES).collect { |t| t.to_s + " " })
      @authors      = dc.xpath('dc:creator/text()|dcterms:creator/text()', NAMESPACES).collect { |t| t.to_s }
      @contributors = dc.xpath('dc:contributor/text()|dcterms:contributor/text()', NAMESPACES).collect { |t| t.to_s + '<br/>' }      
      @source       = dc.at_xpath('dc:source/text()', NAMESPACES).to_s
      @date         = dc.at_xpath('dc:date/text()', NAMESPACES).to_s
      @relation     = dc.at_xpath('dc:relation/text()', NAMESPACES).to_s.gsub /^Collection\s*:\s*/, ''
      @repository   = dc.at_xpath('dc:relation[@type="repository"]', NAMESPACES).to_s
      @collection   = dc.at_xpath('dc:relation[@type="collection"]', NAMESPACES).to_s
      @location     = dc.at_xpath('dc:relation[@type="location"]', NAMESPACES).to_s

      @description  = Array.new
      dc.xpath('dc:description/text()|dcterms:abstract/text()', NAMESPACES).collect { |d| @description.push(d.to_s) }            
    end
    
    # Identity Metadata
    @catalog_key = doc.root.at_xpath('identityMetadata/otherId[@name="catkey"]/text()').to_s
    
    # Content Metadata
    @type = doc.root.xpath('contentMetadata/@type').to_s

    # Book data
    @reading_order = doc.root.xpath('contentMetadata/bookData/@readingOrder').to_s
    @page_start = doc.root.xpath('contentMetadata/bookData/@pageStart').to_s
     
    # File data 
    #@deliverable_files = doc.root.xpath('contentMetadata/resource/file[not(@deliver="no" or @publish="no")]').collect do |file|
    @deliverable_files = Array.new
    
    doc.root.xpath('contentMetadata/resource').collect do |resource_xml|
      file = resource_xml.at_xpath('file')
      resource = Resource.new

      if is_file_ready(file)
        resource.mimetype = file['mimetype']
        resource.size     = file['size']
        resource.shelve   = file['shelve']
        resource.preserve = file['preserve']
        resource.deliver  = file['deliver'] || file['publish']
        resource.filename = file['id']
        resource.objectId = file.parent['objectId']
        resource.type     = file.parent['type'].to_s
        resource.width    = file.at_xpath('imageData/@width').to_s.to_i || 0
        resource.height   = file.at_xpath('imageData/@height').to_s.to_i || 0 

        if (resource.width > 0 and resource.height > 0) 
          resource.levels = (( Math.log([resource.width, resource.height].max) / Math.log(2) ) - ( Math.log(96) / Math.log(2) )).ceil + 1           
        end
    
        resource.imagesvc = file.at_xpath('location[@type="imagesvc"]/text()').to_s
        resource.url      = file.at_xpath('location[@type="url"]/text()').to_s        
      end  
          
      if !resource_xml.at_xpath('attr[@name="label"]/text()').nil?
        resource.description_label = resource_xml.at_xpath('attr[@name="label"]/text()').to_s
      elsif !resource_xml.at_xpath('label/text()').nil?
        resource.description_label = resource_xml.at_xpath('label/text()').to_s
      end

      resource.sequence = resource_xml['sequence'].to_s || 0        
    
      resource.sub_resources = resource_xml.xpath('resource').collect do |sub_resource_xml|
        sub_file = sub_resource_xml.at_xpath('file')
        sub_resource = Resource.new

        if is_file_ready(sub_file)  
          sub_resource.mimetype = sub_file['mimetype']
          sub_resource.size     = sub_file['size']
          sub_resource.shelve   = sub_file['shelve']
          sub_resource.preserve = sub_file['preserve']
          sub_resource.deliver  = sub_file['deliver'] || file['publish']
          sub_resource.filename = sub_file['id']
          sub_resource.objectId = sub_file.parent['objectId']
          sub_resource.type     = sub_file.parent['type']
          sub_resource.width    = sub_file.at_xpath('imageData/@width').to_s.to_i || 0
          sub_resource.height   = sub_file.at_xpath('imageData/@height').to_s.to_i || 0
        
          if (sub_resource.width > 0 and sub_resource.height > 0) 
            sub_resource.levels   = (( Math.log([sub_resource.width, sub_resource.height].max) / Math.log(2) ) - ( Math.log(96) / Math.log(2) )).ceil + 1 
          end
        
          sub_resource.imagesvc = sub_file.at_xpath('location[@type="imagesvc"]/text()').to_s
          sub_resource.url      = sub_file.at_xpath('location[@type="url"]/text()').to_s        
        end  

        if !sub_resource_xml.at_xpath('attr[@name="label"]/text()').nil?
          sub_resource.description_label = sub_resource_xml.at_xpath('attr[@name="label"]/text()').to_s
        elsif !sub_resource_xml.at_xpath('label/text()').nil?
          sub_resource.description_label = sub_resource_xml.at_xpath('label/text()').to_s
        end        
      
        sub_resource.sequence = sub_resource_xml['sequence'].to_s || 0        
      
        sub_resource
      end  
      
      # if the resource has a deliverable file or at least one sub_resource, add it to the array
      if is_file_ready(file) or resource.sub_resources.length > 0
        @deliverable_files.push(resource)
      end
      
    end  
    
    # Rights Metadata
    rights = doc.root.at_xpath('rightsMetadata')
    unless rights.nil?
      read = rights.at_xpath('access[@type="read"]/machine/*')
      
      unless read.nil?
        @read_group = read.name == 'group' ? read.text : read.name
      end
      
      @embargo_release_date = rights.at_xpath(".//embargoReleaseDate/text()").to_s
      
      if( !@embargo_release_date.nil? and @embargo_release_date != '' )
        embargo_date_time = Time.parse(@embargo_release_date)
        @embargo_release_date = '' unless embargo_date_time.future?
      end
      
      @copyright_stmt = rights.at_xpath('copyright/human/text()').to_s 
      @use_and_reproduction_stmt = rights.at_xpath('use/human[@type="useAndReproduction"]/text()').to_s           
      @cclicense_symbol = rights.at_xpath('use/machine[@type="creativeCommons"]/text()').to_s
      
      if (@cclicense_symbol.nil? || @cclicense_symbol.empty?)
        @cclicense_symbol = rights.at_xpath('use/machine[@type="creativecommons"]/text()').to_s
      end
    end
    
    # Properties
    fields = doc.root.at_xpath('fields|properties/fields')
    unless fields.nil?
      @degreeconfyr  = fields.at_xpath("degreeconfyr/text()").to_s
      @cclicense     = fields.at_xpath("cclicense/text()").to_s
      @cclicensetype = fields.at_xpath("cclicensetype/text()").to_s
    end
    @extracted = true
  end
  
  def is_ready?
    if !@public_xml.nil? and !@public_xml.empty? and @public_xml != "<public/>"
      return true
    end
    
    false
  end
  
  # check if this object is of type image
  def is_image?
    if !type.nil? && type =~ /Image|Map/i
      return true
    end  
    
    false
  end

  def is_book?
    if !type.nil? && type =~ /Book|Manuscript/i
      return true
    end  
    
    false
  end  
 
  # check if this object has mods content
  def has_mods
    if !@mods_xml.nil? and !@mods_xml.empty? and @mods_xml != "<mods/>"    
      return true
    end
    
    false
  end    
    
  private

  # retrieve the given document from the document cache for the given object identifier
  def get_metadata(doc_name)
    pair_tree = Purl.create_pair_tree(@pid)
    contents = "<#{doc_name}/>"
    
    unless pair_tree.nil?
      file_path = File.join(DOCUMENT_CACHE_ROOT,pair_tree,doc_name)
      
      if File.exists?(file_path)
        contents = File.read(file_path)
      end
      
      if( !RAILS_ENV.eql? 'production' )
        contents.gsub!('stacks.stanford.edu','stacks-test.stanford.edu')
      end
    end

    return contents
  end
  
  # map the given document public xml to json
  def get_flipbook_json
    self.extract_metadata 
  
    return { 
      :id => "#{@catalog_key}",
      :readGroup => @read_group,
      :objectId => "#{@pid}",
      :defaultViewMode => 2,
      :bookTitle => @titles,
      :readingOrder => @reading_order,  # "rtl"
      :pageStart =>  page_start,  #"left"
      :bookURL => !(@catalog_key.nil? or @catalog_key.empty?) ? "http://searchworks.stanford.edu/view/#{@catalog_key}" : "",
      :pages =>  @deliverable_files.collect { |file| {
          :height => file.height,
          :width => file.width,
          :levels => file.levels,
          :resourceType => file.type,
          :label => @@coder.decode(file.description_label),
          :stacksURL => get_img_base_url(@pid, STACKS_URL,file)          
        }
      }
    }


  end


  def ng_xml(*streams)
    if @ng_xml.nil?
      content = @public_xml

      if content.nil? or content.strip.empty?
        content = "<publicObject objectId='#{@pid}'/>"
      end

      @ng_xml = Nokogiri::XML(content)

      streams.each do |doc_name|
        if @ng_xml.root.at_xpath(%{*[local-name() = "#{doc_name}"]}).nil?
          stream_content = get_metadata(doc_name)
          unless stream_content.empty?
            @ng_xml.root.add_child(Nokogiri::XML(stream_content).root)
          end
        end
      end
    end
    @ng_xml
  end

end
