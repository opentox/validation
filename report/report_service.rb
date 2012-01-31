# = Reports::ReportService
#
# provides complete report webservice functionality
#
module Reports
  
  class ReportService
    
    @@persistance = Reports::ExtendedFileReportPersistance.new
    
    def self.persistance
      @@persistance
    end
    
    def self.instance( home_uri=nil )
      if !defined?@@instance
        @@instance = ReportService.new(home_uri)
      elsif home_uri && @@instance.home_uri != home_uri
        raise "already initialized with different home_uri!!!" 
      end
      @@instance
    end
    
    private
    def initialize(home_uri)
      raise "supposed to be a singleton" if defined?@@instance
      raise "plz specify home_uri" unless home_uri
      LOGGER.info "init report service"
      @home_uri = home_uri
      @@instance = self
    end
  
    public
    # lists all available report types, returns list of uris
    #
    # call-seq:
    #   get_report_types => string
    #
    def get_report_types
      
      LOGGER.info "list all report types"
      Reports::ReportFactory::REPORT_TYPES.collect{ |t| get_uri(t) }.join("\n")+"\n"
    end
    
    # lists all stored reports of a certain type, returns a list of uris
    #
    # call-seq:
    #   get_all_reports(type) => string
    #
    def get_all_reports(type, filter_params)
      
      LOGGER.info "get all reports of type '"+type.to_s+"', filter_params: '"+filter_params.inspect+"'"
      check_report_type(type)
      @@persistance.list_reports(type, filter_params).collect{ |id| get_uri(type,id) }.join("\n")+"\n"
    end
    
    # creates a report of a certain type, __validation_uris__ must contain be a list of validation or cross-validation-uris
    # returns the uir of the report 
    #
    # call-seq:
    #   create_report(type, validation_uris) => string
    # 
    def create_report(type, validation_uris, identifier=nil, params={}, subjectid=nil, task=nil)
      
      raise "params is no hash" unless params.is_a?(Hash)
      LOGGER.info "create report of type '"+type.to_s+"'"
      check_report_type(type)
      
      # step1: load validations
      raise OpenTox::BadRequestError.new("validation_uris missing") unless validation_uris
      LOGGER.debug "validation_uri(s): '"+validation_uris.inspect+"'"
      LOGGER.debug "identifier: '"+identifier.inspect+"'"
      raise "illegal num identifiers: "+identifier.size.to_s+" should be equal to num validation-uris ("+validation_uris.size.to_s+")" if
        identifier and identifier.size!=validation_uris.size
        
      filter_params = nil
      [:min_confidence, :min_num_predictions, :max_num_predictions].each do |key|
        if params[key] != nil
          filter_params = {} unless filter_params
          filter_params[key] = params[key].to_f
        end
      end
      validation_set = Reports::ValidationSet.new(validation_uris, identifier, filter_params, subjectid)
      raise OpenTox::BadRequestError.new("cannot get validations from validation_uris '"+validation_uris.inspect+"'") unless validation_set and validation_set.size > 0
      LOGGER.debug "loaded "+validation_set.size.to_s+" validation/s"
      task.progress(10) if task
      
      #step 2: create report of type
      report_content = Reports::ReportFactory.create_report(type, validation_set, params,
        OpenTox::SubTask.create(task,10,90))
      LOGGER.debug "report created"
      Reports::quit_r
      Reports.validation_access.delete_tmp_resources(subjectid)

      #step 3: persist report if creation not failed
      id = @@persistance.new_report(report_content, type, create_meta_data(type, validation_set, validation_uris), self, subjectid)
      LOGGER.debug "report persisted with id: '"+id.to_s+"'"
      task.progress(100) if task
      
      #HACK - format to html right after creation, as dynamically create html may cause deadlocks 
      get_report(type, id, "text/html")
      
      return get_uri(type, id)
    end
    
    # yields report in a certain format, converts to this format if not yet exists, returns uri of report on server 
    #
    # call-seq:
    #   get_report( type, id, accept_header_value ) => string
    # 
    def get_report( type, id, accept_header_value="text/xml", force_formating=false, params={} )
      
      LOGGER.info "get report '"+id.to_s+"' of type '"+type.to_s+"' (accept-header-value: '"+
        accept_header_value.to_s+"', force-formating:"+force_formating.to_s+" params: '"+params.inspect+"')"
      check_report_type(type)
      format = Reports::ReportFormat.get_format(accept_header_value)
      return @@persistance.get_report(type, id, format, force_formating, params)
    end
    
    # returns a report resource (i.e. image)
    #
    # call-seq:
    #   get_report_resource( type, id, resource ) => string
    # 
    def get_report_resource( type, id, resource )
      
      LOGGER.info "get resource '"+resource+"' for report '"+id.to_s+"' of type '"+type.to_s+"'"
      check_report_type(type)
      return @@persistance.get_report_resource(type, id, resource)
    end
    
    
    # delets a report
    #
    # call-seq:
    #   delete_report( type, id )
    # 
    def delete_report( type, id, subjectid=nil )
      
      LOGGER.info "delete report '"+id.to_s+"' of type '"+type.to_s+"'"
      check_report_type(type)
      @@persistance.delete_report(type, id, subjectid)
    end
    
    # no api-access for this method
    def delete_all_reports( type, subjectid=nil )
      
      LOGGER.info "deleting all reports of type '"+type.to_s+"'"
      check_report_type(type)
      @@persistance.list_reports(type).each{ |id| @@persistance.delete_report(type, id, subjectid) }
    end
    
    def parse_type( report_uri )
      
      raise "invalid uri" unless report_uri.to_s =~/^#{@home_uri}.*/
      type = report_uri.squeeze("/").split("/")[-2]
      check_report_type(type)
      return type
    end
    
    def parse_id( report_uri )
      
      raise "invalid uri" unless report_uri.to_s =~/^#{@home_uri}.*/
      id = report_uri.squeeze("/").split("/")[-1]
      @@persistance.check_report_id_format(id)
      return id
    end
    
    def home_uri
      @home_uri
    end
    
    def get_uri(type, id=nil)
      @home_uri+"/"+type.to_s+(id!=nil ? "/"+id.to_s : "")
    end
    
    protected
    def create_meta_data(type, validation_set, validation_uris)
      # the validation_set contains the resolved single validations
      # crossvalidation uris are only added if given as validation_uris - param
      meta_data = {}
      { :validation_uri => "validation_uris",  
          :model_uri => "model_uris",
          :algorithm_uri => "algorithm_uris" }.each do |key,data|
        tmp = []
        validation_set.validations.each do |v|
          #tmp << v.send(key) if v.public_methods.include?(key.to_s) and v.send(key) and !tmp.include?(v.send(key))
          tmp << v.send(key) if v.send(key) and !tmp.include?(v.send(key))
        end
        meta_data[data.to_sym] = tmp
      end
      cvs = []
      validation_uris.each do |v|
        cvs << v if v =~ /crossvalidation/ and !cvs.include?(v)
      end
      meta_data[:crossvalidation_uris] = cvs
      
      meta_data
    end
    
    def check_report_type(type)
     raise OpenTox::NotFoundError.new("report type not found '"+type.to_s+"'") unless Reports::ReportFactory::REPORT_TYPES.index(type)
    end
    
  end
end
