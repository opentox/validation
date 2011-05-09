
REPORT_DIR = File.join(Dir.pwd,'/reports')
require "lib/format_util.rb"

# = Reports::ReportPersistance
#
# service that stores reports (Reports::ReportConent), and provides access in various formats
#
class Reports::ReportPersistance
  
  # lists all stored report ID-s of a certain type
  #
  # call-seq:
  #   list_reports(type) => Array
  #
  def list_reports(type, filter_params)
    raise "not implemented"
  end
  
  # stores content of a report (Reports::ReportContent) and returns id
  #
  # call-seq:
  #   new_report(report_content) => string
  #
  def new_report(report_content)
    raise "not implemented"
  end
  
  # returns a already created report (file path on server) in a certain format (converts to this format if it does not exist yet)
  #
  # call-seq:
  #   get_report(type, id, format) => string
  #
  def get_report(type, id, format, force_formating, params)
    raise "not implemented"
  end
  
  # returns file path on server of a resource (i.e. image) of a report 
  #
  # call-seq:
  #   get_report_resource(type, id, resource) => string
  #
  def get_report_resource(type, id, resource)
    raise "not implemented"
  end
  
  # deletes a report
  # * returns true if deleting successfull
  # * returns false if report not found
  # * raises exception if error occurs
  #
  # call-seq:
  #   delete_report(type, id) => boolean
  #
  def delete_report(type, id, subjectid=nil)
    raise "not implemented"
  end
  
  # raises exception if not valid id format
  def check_report_id_format(id)
    raise "not implemented"
  end
  
end

# = Reports::FileReportPersistance
#
# type of Reports::ReportPersistance, stores reports in file-system, see Reports::ReportPersistance for API documentation
#
class Reports::FileReportPersistance < Reports::ReportPersistance
  
  def initialize()
    FileUtils.mkdir REPORT_DIR unless File.directory?(REPORT_DIR)
    raise "report cannot be found nor created" unless File.directory?(REPORT_DIR)
    LOGGER.debug "reports are stored in "+REPORT_DIR 
  end
  
  def list_reports(type, filter_params=nil)
    raise "filter params not supported" if filter_params
    (Dir.new(type_directory(type)).entries - [".", ".."]).sort{|x,y| x.to_i <=> y.to_i}
  end
  
  def get_report(type, id, format, force_formating, params)
    
    report_dir = report_directory(type, id)
    raise_report_not_found(type, id) unless File.directory?(report_dir)
    
    filename = "report."+Reports::ReportFormat.get_filename_extension(format)
    file_path = report_dir+"/"+filename
    
    return file_path if File.exist?(file_path) && !force_formating
      
    Reports::ReportFormat.format_report(report_dir, "report.xml", filename, format, force_formating, params)
    raise "formated file not found '"+file_path+"'" unless File.exist?(file_path)
    return file_path
  end
  
  def get_report_resource(type, id, resource)
    
    report_dir = report_directory(type, id)
    raise_report_not_found(type, id) unless File.directory?(report_dir)
    file_path = report_dir+"/"+resource.to_s
    raise OpenTox::NotFoundError.new("resource not found, resource: '"+resource.to_s+"', type:'"+type.to_s+"', id:'"+id.to_s+"'") unless File.exist?(file_path)
    return file_path
  end
  
  def delete_report(type, id, subjectid=nil)
    
    report_dir = report_directory(type, id)
    raise_report_not_found(type, id) unless File.directory?(report_dir)
    
    entries = (Dir.new(report_dir).entries-[".", ".."]).collect{|f| report_dir+"/"+f.to_s}
    FileUtils.rm(entries)
    FileUtils.rmdir report_dir
    raise "could not delete report directory '"+report_dir+"'" if File.directory?(report_dir)
    return true
  end
  
  def check_report_id_format(id)
    raise "not valid report id format" unless id.to_s =~ /[0-9]+/
  end
  
  def new_report(report_content, type, meta_data=nil, uri_provider=nil)
    new_report_with_id(report_content, type)
  end
  
  protected
  def new_report_with_id(report_content, type, force_id=nil)
    LOGGER.debug "storing new report of type "+type.to_s 
    
    type_dir = type_directory(type)
    raise "type dir '"+type_dir+"' cannot be found nor created" unless File.directory?(type_dir)
    
    if (force_id==nil)
      id = 1
      while File.exist?( type_dir+"/"+id.to_s )
        id += 1
      end
    else
      raise "report with id '"+force_id.to_s+"' already exists, file system not consistent with db" if File.exist?( type_dir+"/"+force_id.to_s )
      id = force_id      
    end
    report_dir = type_dir+"/"+id.to_s
    FileUtils.mkdir(report_dir)
    raise "report dir '"+report_dir+"' cannot be created" unless File.directory?(report_dir)
    
    xml_filename = report_dir+"/report.xml"
    xml_file = File.new(xml_filename, "w")
    report_content.xml_report.write_to(xml_file, id)
    xml_file.close
    if (report_content.tmp_files)
      report_content.tmp_files.each do |k,v|
        tmp_filename = report_dir+"/"+k
        raise "tmp-file '"+tmp_filename.to_s+"' already exists" if File.exist?(tmp_filename)
        raise "tmp-file '"+v.to_s+"' not found" unless File.exist?(v)
        FileUtils.mv(v.to_s,tmp_filename)
        raise "could not move tmp-file to '"+tmp_filename.to_s+"'" unless File.exist?(tmp_filename)
      end
    end
    return id
  end
  
  private
  def raise_report_not_found(type, id)
    raise OpenTox::NotFoundError.new("report not found, type:'"+type.to_s+"', id:'"+id.to_s+"'")
  end
  
  def type_directory(type)
    dir = REPORT_DIR+"/"+type
    FileUtils.mkdir dir.to_s unless (File.directory?(dir))
    return dir
  end
  
  def report_directory(type, id)
    type_dir = type_directory(type)
    raise "type dir '"+type_dir+"' cannot be found nor created" unless File.directory?(type_dir)
    return type_dir+"/"+id.to_s
  end
  
end

module Reports
  
  #class ReportData < ActiveRecord::Base
#    serialize :validation_uris
#    serialize :crossvalidation_uris
#    serialize :algorithm_uris
#    serialize :model_uris
#    alias_attribute :date, :created_at

  class ReportData < Ohm::Model
  
    attribute :report_type
    attribute :created_at
    attribute :validation_uris 
    attribute :crossvalidation_uris
    attribute :model_uris
    attribute :algorithm_uris    
    
    index :report_type
    index :validation_uris
    index :crossvalidation_uris
    
    attr_accessor :subjectid
    
    def save
      super
      OpenTox::Authorization.check_policy(report_uri, subjectid)
    end
    
    public
    def date
      created_at
    end
    
    def report_uri
      raise "no id" if self.id==nil
      Reports::ReportService.instance.get_uri(self.report_type, self.id)
    end
    
    def get_content_as_hash
      map = {}
      [ :date, :report_type, :validation_uris, :crossvalidation_uris,
        :algorithm_uris, :model_uris ].each do |p| 
        map[p] = self.send(p)
      end
      map
    end
    
    def to_yaml
      get_content_as_hash.keys_to_rdf_format.keys_to_owl_uris.to_yaml
    end    
    
    def to_rdf
      s = OpenTox::Serializer::Owl.new
      s.add_resource(report_uri,OT.Report,get_content_as_hash.keys_to_rdf_format.keys_to_owl_uris)
      s.to_rdfxml
    end
  end
  
  class ExtendedFileReportPersistance < FileReportPersistance
    
    def new_report(report_content, type, meta_data, uri_provider, subjectid=nil)
      raise "report meta data missing" unless meta_data
      report = ReportData.new(meta_data)
      report.subjectid = subjectid
      report.report_type = type
      report.save
      OpenTox::Authorization.check_policy(report.report_uri, subjectid)
      new_report_with_id(report_content, type, report.id)
    end
    
    def list_reports(type, filter_params={})
      LOGGER.debug "find reports for params: "+filter_params.inspect
      reports = Lib::OhmUtil.find( ReportData, filter_params )
      reports.collect{ |r| r.id }
    end
    
    def get_report(type, id, format, force_formating, params)
      
      report = ReportData[id]
      raise OpenTox::NotFoundError.new("Report with id='"+id.to_s+"' and type='"+type.to_s+"' not found.") if 
        report==nil or report.report_type!=type
#      begin
#        report = ReportData.find(:first, :conditions => {:id => id, :report_type => type})
#      rescue ActiveRecord::RecordNotFound
#        raise OpenTox::NotFoundError.new("Report with id='"+id.to_s+"' and type='"+type.to_s+"' not found.")
#      end
  
      case format
      when "application/rdf+xml"
        report.to_rdf
      when "application/x-yaml"
        report.to_yaml
      else
        super
      end
    end
    
    def delete_report(type, id, subjectid=nil)
#      begin
#        report = ReportData.find(:first, :conditions => {:id => id, :report_type => type})
#      rescue ActiveRecord::RecordNotFound
#        raise OpenTox::NotFoundError.new("Report with id='"+id.to_s+"' and type='"+type.to_s+"' not found.")
#      end
#      ReportData.delete(id)
      report = ReportData[id]
      raise OpenTox::NotFoundError.new("Report with id='"+id.to_s+"' and type='"+type.to_s+"' not found.") if
        report==nil || report.report_type!=type
      report.delete
      if (subjectid)
        begin
          res = OpenTox::Authorization.delete_policies_from_uri(report.report_uri, subjectid)
          LOGGER.debug "Deleted validation policy: #{res}"
        rescue
          LOGGER.warn "Policy delete error for validation: #{report.report_uri}"
        end
      end
      super      
    end
  end
end

#module Reports
#  def self.check_filter_params(model, filter_params)
#    prop_names = model.properties.collect{|p| p.name.to_s}
#    filter_params.keys.each do |k|
#      key = k.to_s
#      unless prop_names.include?(key)
#        key = key.from_rdf_format
#        unless prop_names.include?(key)
#          key = key+"_uri"
#          unless prop_names.include?(key)
#            key = key+"s"
#            unless prop_names.include?(key)
#              err = "no attribute found: '"+k.to_s+"'"
#              if $sinatra
#                $sinatra.halt 400,err
#              else
#                raise err
#              end
#            end
#          end
#        end
#      end
#      filter_params[key] = filter_params.delete(k)
#    end
#    filter_params
#  end
#  
#  def ReportData.all( params )
#    super Reports.check_filter_params( ReportData, params )
#  end
#end
