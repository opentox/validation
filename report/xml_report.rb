#['rubygems', 'rexml/document' ].each do |g|
#    require g
#end

require "./report/xml_report_util.rb"

ENV['DOCBOOK_DIRECTORY'] = "docbook-xml-4.5" unless ENV['DOCBOOK_DIRECTORY']
ENV['REPORT_DTD'] = "docbookx.dtd" unless ENV['REPORT_DTD']

#transfer to absolute path
#ENV['REPORT_DTD'] = File.expand_path(ENV['REPORT_DTD']) if File.exist?(ENV['REPORT_DTD'])


# = XMLReport
# 
# uses REXML to generate an XML document in DocBook article format
#
# uses Env-Variable _XMLREPORT_DTD_ to specifiy the dtd
#  
module Reports
  class XMLReport
    include REXML
    
    def self.dtd_directory
      if $url_provider
        $url_provider.to("/validation/"+ENV['DOCBOOK_DIRECTORY']+'/'+ENV['REPORT_DTD'], :full)
      else
        f = File.expand_path(File.join(ENV['DOCBOOK_DIRECTORY'],ENV['REPORT_DTD']))
        internal_server_error "cannot find dtd" unless File.exist?(f)
        f
      end
    end
    
    # create new xmlreport
    def initialize(title, pubdate=nil, author_firstname = nil, author_surname = nil)
      
      @doc = Document.new
      decl = XMLDecl.new
      @doc << decl
      type = DocType.new('article PUBLIC "-//OASIS//DTD DocBook XML V4.5//EN" "'+XMLReport.dtd_directory+'"')
      @doc << type
  
      @root = Element.new("article")
      @doc << @root
  
      article_info = Element.new("articleinfo")
      article_info << Reports::XMLReportUtil.text_element("title", title)
      author = Element.new("author")
      author << Reports::XMLReportUtil.text_element("firstname", author_firstname)
      author << Reports::XMLReportUtil.text_element("surname", author_surname)
      article_info << author
      article_info << Reports::XMLReportUtil.text_element("pubdate", pubdate)
      @root << article_info
      
      @resource_path_elements = {}
    end
    
    # 
    # returns the root element of the document
    # call-seq:
    #   get_root_element => REXML::Element
    #
    def get_root_element
      @root
    end
    
    # adds a new section to a REXML:Element, returns the section as element
    # call-seq:
    #   add_section(element, title) => REXML::Element
    #
    def add_section(element, title)
      
      section = Element.new("section")
      section << Reports::XMLReportUtil.text_element("title", title)
      element << section
      return section
    end
    
    # adds a new paragraph to a REXML:Element, returns the paragraph as element
    # call-seq:
    #   add_paragraph( element, text ) => REXML::Element
    #
    def add_paragraph( element, text, literallayout=false )
      
      unless literallayout
        para = Reports::XMLReportUtil.text_element("para", text)
        element << para
        return para
      else
        literal = Reports::XMLReportUtil.text_element("literallayout", Text.new(text,true))
        element << literal
        return literal
      end
    end
    
    def imagefigure( title, path, filetype, size_pct=100, altPath = nil )
      figure = Reports::XMLReportUtil.attribute_element("figure", {"float" => 0})
      figure << Reports::XMLReportUtil.text_element("title", title)
      
      #media = Element.new("mediaobject")
      media = Element.new("inlinemediaobject")
      image = Element.new("imageobject")
      imagedata = Reports::XMLReportUtil.attribute_element("imagedata",
         {"fileref" => path, "format"=>filetype, "contentwidth" => size_pct.to_s+"%",
         #"contentdepth"=> "4in" 
         })#"width" => "6in", "height" => "5in"}) #"contentwidth" => "100%"})
      #imagedata = Reports::XMLReportUtil.attribute_element("imagedata",{"width" => "6in", "fileref" => path, "format"=>filetype})
      @resource_path_elements[imagedata] = "fileref"
      image << imagedata
      media << image
      #media << Reports::XMLReportUtil.text_element("caption", caption) if caption
      #figure << media
      
      ulink = Element.new("ulink")
      ulink.add_attributes({"url" => altPath ? altPath : path })
      @resource_path_elements[ulink] = "url"
      ulink << media
      
      figure << ulink
      figure
    end
    
    # adds a new image to a REXML:Element, returns the figure as element
    # 
    # example: <tt>add_imagefigure( section2, "Nice graph", "/images/graph1.svg", "SVG", "This graph shows..." )</tt>
    #
    # call-seq:
    #   add_imagefigure( element, title, path, filetype, caption = nil ) => REXML::Element
    #
    def add_imagefigure( element, title, path, filetype, size_pct=100, altPath = nil )
      figure = imagefigure( title, path, filetype, size_pct, altPath)
      element << figure
      return figure 
    end
    
    # bit of a hack to algin the last two figures that have been added to element into one row
    def align_last_two_images( element, title  )
      imgs = []
      element.elements.each do |e|
        imgs[0] = imgs[1]
        imgs[1] = e if e.name=="figure"
      end
      if (imgs[0] and imgs[1])
        element.delete_element imgs[0]
        element.delete_element imgs[1]
        add_imagefigures_in_row( element, imgs, title )
      end
    end

    def add_imagefigures_in_row( element, imagefigures, title )
      params = {"frame" => "none", "colsep" => 0, "rowsep" => 0 }
      table = Reports::XMLReportUtil.attribute_element("table",params)
      table << Reports::XMLReportUtil.text_element("title", title)
      tgroup = Reports::XMLReportUtil.attribute_element("tgroup",{"cols" => 2})
      tbody = Element.new("tbody") 
      row = Element.new("row")
      imagefigures.each do |f|
        entry = Element.new("entry")
        entry << f
        row << entry
      end
      tbody << row
      tgroup << tbody 
      table << tgroup
      element << table
      table
    end
    
    def add_image( element, url ) #, scale=false )
      image = Element.new("imageobject")
      params = {"fileref" => url, "format"=>"PNG"}
      #params["contentwidth"] = "2in"
      imagedata = Reports::XMLReportUtil.attribute_element("imagedata",params) 
      image << imagedata
      element << image
      return image    
    end
    
    # adds a table to a REXML:Element, _table_values_ should be a multi-dimensional-array, returns the table as element
    # 
    # call-seq:
    #   add_table( element, title, table_values, first_row_header=true ) => REXML::Element
    #
    def add_table( element, title, table_values, first_row_header=true, first_col_header=false, transpose=false, auto_link_urls=true )
      
      internal_server_error "table_values is not multi-dimensional-array" unless table_values && table_values.is_a?(Array) && table_values[0].is_a?(Array) 
      
      values = transpose ? table_values.transpose : table_values
      
      params = {"frame" => "none", "colsep" => 1, "rowsep" => 1 }
      params["rowheader"] = "firstcol" if first_col_header
      table = Reports::XMLReportUtil.attribute_element("table",params)
      
      table << Reports::XMLReportUtil.text_element("title", title)
      
      internal_server_error "column count 0" if values.at(0).size < 1 
      
      tgroup = Reports::XMLReportUtil.attribute_element("tgroup",{"cols" => values.at(0).size})
      
      table_body_values = values
      
      if first_row_header
        table_head_values = values[0];
        table_body_values = values[1..-1];
        
        thead = Element.new("thead")
        row = Element.new("row")
        table_head_values.each do |v|
          entry = Element.new("entry")
          if auto_link_urls && v.to_s =~ /^http(s?):\/\//
            add_url(entry, v.to_s)
          else
            entry.text = v.to_s
          end
          row << entry
        end
        thead << row
        tgroup << thead
      end
      
      tbody = Element.new("tbody") 
      table_body_values.each do |r|
        row = Element.new("row")
        r.each do |v|
          entry = Element.new("entry")
          if auto_link_urls && v.to_s =~ /depict/ || v.to_s =~ /png$/ #PENDING 
            add_image(entry, v.to_s)
          elsif auto_link_urls && v.to_s =~ /^http(s?):\/\//
           #add_url(entry, v.to_s, v.to_s)
           v.to_s.split(" ").each do |vv|
              add_url(entry, vv.to_s, vv.to_s)
              space = Element.new("para")
              space.text = " "
              entry << space
           end
         else
           text = v.to_s
           text.gsub!(/\+\-/,"&plusmn;")
           entry << Text.new(text, true, nil, true)
          end
          row << entry
        end
        tbody << row
      end
      tgroup << tbody 
      
      table << tgroup
      element << table
      return table
    end
    
    # adds a list to a REXML:Element, returns the list as element
    # 
    # call-seq:
    #   add_list( element, list_values ) => REXML::Element
    #
    def add_list( element, list_values )
      
      list = Element.new("itemizedlist")
      
      list_values.each do |l|
        listItem = Element.new("listitem")
        add_paragraph(listItem, l.to_s)
        list << listItem
      end
      
      element << list
      return list
    end
    
    def url_element( url, description=url )
      ulink = Element.new("ulink")
      ulink.add_attributes({"url" => url})
      ulink.text = description
      ulink
    end
    
    def add_url (element, url, description=url )
      ulink = url_element(url, description)
      element << ulink
      return ulink
    end
    
    # writes xml document
    def write_to( out = $stdout, resource_path=nil )
      
      #alternativly use base href in html-header
      if (resource_path)
        @resource_path_elements.each do |k,v|
          internal_server_error "attribute '"+v+"' not found in element '"+k+"'" unless k.attributes.has_key?(v)
          k.add_attribute( v, resource_path.to_s+"/"+k.attributes[v].to_s )
        end
      end
      
      @doc.write(out) #,2, true, true)
      out.flush
    end
  
    # call-seq:
    #   self.generate_demo_xml_report => Reports::XMLReport
    #
    def self.generate_demo_xml_report
  
      rep = Reports::XMLReport.new("Demo report", "subtitle" "Fistname", "Surname")
      section1 = rep.add_section(rep.get_root_element, "First Section")
      rep.add_paragraph(section1, "some text")
      rep.add_paragraph(section1, "even more text")
      rep.add_imagefigure(section1, "Figure", "http://upload.wikimedia.org/wikipedia/commons/thumb/e/eb/Siegel_der_Albert-Ludwigs-Universit%C3%A4t_Freiburg.svg/354px-Siegel_der_Albert-Ludwigs-Universit%C3%A4t_Freiburg.svg", "SVG", 100, "this is the logo of freiburg university")
      section2 = rep.add_section(rep.get_root_element,"Second Section")
      rep.add_section(section2,"A Subsection")
      rep.add_section(section2,"Another Subsection")
      rep.add_url(section2,"www.google.de", "link zu google")
      sec3 = rep.add_section(rep.get_root_element,"Third Section")
      rep.add_paragraph(sec3, "some    \n              more text for section 3",true)
      rep.add_image(sec3, "http://ambit.uni-plovdiv.bg:8080/ambit2/depict/cdk?search=c1ccccc1")
      
      #vals= [["a", "b", "c"],["a2", "b2", "c2"],["1", "2", "http://3"]]
      #rep.add_table(rep.get_root_element, "demo-table", vals)
      return rep
    end
  end
end


#Reports::XMLReport.generate_demo_xml_report.write_to
#puts "\n\n"
#puts REXML::Text.new("hey ho,                       lets go!\nasdf",false).to_s












  
