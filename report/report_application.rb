require "./report/environment.rb"

class Validation::Application < OpenTox::Service

  def perform
    @@report_service = Reports::ReportService.instance( to("/validation/report", :full) ) unless defined?@@report_service  
    yield( @@report_service )
  end
  
  def get_docbook_resource(filepath)
    perform do |rs|
      resource_not_found_error <"not found: "+filepath unless File.exist?(filepath)
      types = MIME::Types.type_for(filepath)
      content_type(types[0].content_type) if types and types.size>0 and types[0]
      result = body(File.new(filepath))
    end
  end
  
  get '/validation/'+ENV['DOCBOOK_DIRECTORY']+'/:subdir/:resource' do
    path_array = request.env['REQUEST_URI'].split("/")
    get_docbook_resource ENV['DOCBOOK_DIRECTORY']+"/"+path_array[-2]+"/"+path_array[-1]
  end
  
  get '/validation/'+ENV['DOCBOOK_DIRECTORY']+'/:resource' do
    get_docbook_resource ENV['DOCBOOK_DIRECTORY']+"/"+request.env['REQUEST_URI'].split("/")[-1]
  end
  
  get '/validation/resources/:resource' do
    get_docbook_resource "resources/"+request.env['REQUEST_URI'].split("/")[-1]
  end
  
  get '/validation/report/:type/css_style_sheet/?' do
    perform do |rs|
      "@import \""+params[:css_style_sheet]+"\";"
    end
  end
  
  get '/validation/report/?' do
    perform do |rs|
      case request.env['HTTP_ACCEPT'].to_s
      when  /text\/html/
        related_links =
          "All validations: "+to("/validation/",:full)
        description = 
          "A list of all report types."
        content_type "text/html"
        rs.get_report_types.to_html(related_links,description)
      else
        content_type "text/uri-list"
        rs.get_report_types
      end
    end
  end
  
  def wrap(s, width=78)
    s.gsub(/(.{1,#{width}})(\s+|\Z)/, "\\1\n")
  end
  
  get '/validation/report/:report_type' do
    perform do |rs|
      case request.env['HTTP_ACCEPT'].to_s
      when  /text\/html/
        related_links =
          "Available report types: "+to("/validation/report",:full)+"\n"+
          "Single validations:     "+to("/validation/",:full)+"\n"+
          "Crossvalidations:       "+to("/validation/crossvalidation",:full)
        description = 
          "A list of all "+params[:report_type]+" reports. To create a report, use the POST method."
        if params[:report_type]=="algorithm_comparison"
          description += "\n\nThis report can be used to compare the validation results of different algorithms that have been validated on the same dataset."
          description += "\nThe following attributes can be compared with the t-test:"
          description += "\n\n* All validation types:\n"+wrap((Validation::VAL_PROPS_SUM+Validation::VAL_PROPS_AVG).join(", "),120)
          description += "\n* Classification validations:\n"+wrap(Validation::VAL_CLASS_PROPS.join(", "),120)
          description += "\n* Regresssion validations:\n"+wrap(Validation::VAL_REGR_PROPS.join(", "),120)
        end
          
        post_params = [[:validation_uris]]
        #post_command = OpenTox::PostCommand.new request.url,"Create validation report"
        #val_uri_description = params[:report_type]=="algorithm_comparison" ? "Separate multiple uris with ','" : nil
        # trick for easy report creation
        # if searching for a report, ?validation="uri" or ?crossvalidaiton="uri" is given as search param
        # use this (search param has equal name as report type) as default value for validation_uri 
        # post_command.attributes << OpenTox::PostAttribute.new("validation_uris",true,params[params[:report_type]],val_uri_description)
        # if params[:report_type]=="algorithm_comparison"
          # post_command.attributes << OpenTox::PostAttribute.new("identifier",true,nil,"Specifiy one identifier for each uri, separated with ','")
          # post_command.attributes << OpenTox::PostAttribute.new("ttest_significance",false,"0.9","Significance level for t-tests (Set to '0' to disable t-test).")
          # post_command.attributes << OpenTox::PostAttribute.new("ttest_attributes",false,nil,"Attributes for t-test; default for classification: '"+
            # VAL_ATTR_TTEST_CLASS.join(",")+"', default for regression: '"+VAL_ATTR_TTEST_REGR.join(",")+"'")
        # end
        content_type "text/html"
        rs.get_all_reports(params[:report_type], params).to_html related_links,description#,post_command
      else
        content_type "text/uri-list"
        rs.get_all_reports(params[:report_type], params)
      end
    end
  end
  
  post '/validation/report/:type/:id/format_html' do
    perform do |rs| 
      rs.get_report(params[:type],params[:id],"text/html",true,params)
      content_type "text/uri-list"
      rs.get_uri(params[:type],params[:id])+"\n"
    end
  end
  
  
  get '/validation/report/:type/:id' do
    perform do |rs| 
      
      accept_header = request.env['HTTP_ACCEPT']
      report = rs.get_report(params[:type],params[:id],accept_header)
      format = Reports::ReportFormat.get_format(accept_header)
      content_type format
      # default encoding is utf-8, html conversion produces iso-8859-1 encoding
      content_type "text/html", 'charset' => 'ISO-8859-1' if format=="text/html"
      #PENDING: get_report should return file or string, check for result.is_file instead of format
      if format=="application/x-yaml" or format=="application/rdf+xml"
        report
      else
        result = body(File.new(report))
      end
    end
  end
  
  #OpenTox::Authorization.whitelist( Regexp.new("/report/.*/[0-9]+/.*"),"GET")
  
  get '/validation/report/:type/:id/:resource' do
    perform do |rs|
      filepath = rs.get_report_resource(params[:type],params[:id],params[:resource])
      types = MIME::Types.type_for(filepath)
      content_type(types[0].content_type) if types and types.size>0 and types[0]
      result = body(File.new(filepath))
    end
  end
  
  delete '/validation/report/:type/:id' do
    perform do |rs|
      content_type "text/plain"
      rs.delete_report(params[:type],params[:id],@subjectid)
    end
  end
  
  post '/validation/report/:type' do
    bad_request_error "validation_uris missing" unless params[:validation_uris].to_s.size>0
    task = OpenTox::Task.run("Create report",to("/validation/report/"+params[:type], :full)) do |task| #,params
      perform do |rs|
        puts rs.inspect
        rs.create_report(params[:type],params[:validation_uris]?params[:validation_uris].split(/\n|,/):nil,
          params[:identifier]?params[:identifier].split(/\n|,/):nil,params,@subjectid,task)
      end
    end
    return_task(task)
  end
end
