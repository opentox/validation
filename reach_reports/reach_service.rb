
class Array

  def to_html
    return "" unless size>0
    s = "<html>\n<head>\n</head>\n<body>\n"
    s += join(" <br>\n")
    s += "</body>\n</html>\n"
    return s
  end
end
  
module ReachReports
  
  def self.list_reports(type, model_uri=nil)
    case type
    when /(?i)QMRF/
      params = {}
      params[:model_uri]=model_uri if model_uri
      ReachReports::QmrfReport.all(params).collect{ |r| r.report_uri }.join("\n")+"\n"
    when /(?i)QPRF/
      ReachReports::QprfReport.all.collect{ |r| r.report_uri }.join("\n")+"\n"
    end
  end 
  
  def self.create_report( type, params, subjectid, xml_data=nil )
    
    case type
    when /(?i)QMRF/
      if params[:model_uri]
        task = OpenTox::Task.create( "Create "+type+" report", 
          $url_provider.url_for("/reach_report/"+type, :full) ) do |task| #, params
            
          report = ReachReports::QmrfReport.new :model_uri => params[:model_uri]
          report.subjectid = subjectid
          build_qmrf_report(report, task)
          report.report_uri
        end
        result_uri = task.uri
      elsif xml_data and (input = xml_data.read).to_s.size>0
        report = ReachReports::QmrfReport.new
        report.subjectid = subjectid
        ReachReports::QmrfReport.from_xml(report,input)
        result_uri = report.report_uri
      else
        raise OpenTox::BadRequestError.new "illegal parameters for qmrf-report creation, either\n"+
          "* give 'model_uri' as param\n"+
          "* provide xml file\n"+
          "params given: "+params.inspect
      end
    when /(?i)QPRF/
      raise OpenTox::BadRequestError.new "qprf report creation not yet implemented"
      if params[:compound_uri]
        #report = ReachReports::QprfReport.new :compound_uri => params[:compound_uri]
      else
        raise OpenTox::BadRequestError.new "illegal parameters for qprf-report, use either\n"+
          "* compound-uri\n"+ 
          "params given: "+params.inspect
      end
    end
    result_uri
  end
  
  def self.build_qmrf_report(r, task=nil)
    
    #puts r.model_uri
    model = OpenTox::Model::Generic.find(r.model_uri, r.subjectid)
    feature_type = model.feature_type(r.subjectid)
    
    # chapter 1
    r.qsar_identifier = QsarIdentifier.new
    r.qsar_identifier.qsar_title = model.metadata[DC.title]
    # TODO QSAR_models -> sparql same endpoint     
    r.qsar_identifier.qsar_software << QsarSoftware.new( :url => model.uri, 
      :name => model.metadata[DC.title], :contact => model.metadata[DC.creator] )
    algorithm = OpenTox::Algorithm::Generic.find(model.metadata[OT.algorithm], r.subjectid) if model.metadata[OT.algorithm]
    r.qsar_identifier.qsar_software << QsarSoftware.new( :url => algorithm.uri, :name => algorithm.metadata[DC.title] )
    task.progress(10) if task

    #chpater 2
    r.qsar_general_information = QsarGeneralInformation.new
    r.qsar_general_information.qmrf_date = DateTime.now.to_s
    # EMPTY: qmrf_authors, qmrf_date_revision, qmrf_revision
    # TODO: model_authors ?
    r.qsar_general_information.model_date = model.metadata[DC.date].to_s
    # TODO: references?
    # EMPTY: info_availablity
    # TODO: related_models = find qmrf reports for QSAR_models 
    task.progress(20) if task
    
    # chapter 3
    # TODO "model_species" ?
    r.qsar_endpoint = QsarEndpoint.new
    model.metadata[OT.predictedVariables].each do |p|
      r.qsar_endpoint.model_endpoint << ModelEndpoint.new( :name => p )
    end if model.metadata[OT.predictedVariables]
    # TODO "endpoint_comments" => "3.3", "endpoint_units" => "3.4",
    r.qsar_endpoint.endpoint_variable =  model.metadata[OT.dependentVariables] if model.metadata[OT.dependentVariables]
    # TODO "endpoint_protocol" => "3.6", "endpoint_data_quality" => "3.7",
    task.progress(30) if task
    
    # chapter 4
    # TODO algorithm_type (='type of model')
    # TODO algorithm_explicit.equation
    # TODO algorithm_explicit.algorithms_catalog
    # TODO algorithms_descriptors, descriptors_selection, descriptors_generation, descriptors_generation_software, descriptors_chemicals_ratio
    task.progress(40) if task

    # chapter 5
    # TODO app_domain_description, app_domain_method, app_domain_software, applicability_limits

    #training_dataset = model.trainingDataset ? OpenTox::Dataset.find(model.trainingDataset+"/metadata") : nil
    if ( OpenTox::Dataset.exist?(model.metadata[OT.trainingDataset], r.subjectid) )
      training_dataset = OpenTox::Dataset.new( model.metadata[OT.trainingDataset], r.subjectid )
      training_dataset.load_metadata( r.subjectid )
    else
      training_dataset = nil
      LOGGER.warn "build qmrf: training_dataset not found "+model.metadata[OT.trainingDataset].to_s
    end
    task.progress(50) if task

    # chapter 6
    r.qsar_robustness = QsarRobustness.new
    if training_dataset
      r.qsar_robustness.training_set_availability = "Yes"
      r.qsar_robustness.training_set_data = TrainingSetData.new(:chemname => "Yes", :cas => "Yes", 
        :smiles => "Yes", :inchi => "Yes", :mol => "Yes", :formula => "Yes")
    end
    
    #TODO "training_set_data" => "6.2",
    # "training_set_descriptors" => "6.3", 
    # "dependent_var_availability" => "6.4", "other_info" => "6.5", "preprocessing" => "6.6", "goodness_of_fit" => "6.7", 
    # "loo" => "6.8",
    
    val_datasets = []
    
    if algorithm
      cvs = Validation::Crossvalidation.find_all_uniq({:algorithm_uri => algorithm.uri, :finished => true},r.subjectid)
      # PENDING: cv classification/regression hack
      cvs = cvs.delete_if do |cv|
        #val = Validation::Validation.first( :all, :conditions => { :crossvalidation_id => cv.id } )
        val = Validation::Validation.find( :crossvalidation_id => cv.id ).first
        raise "should not happen: no validations found for crossvalidation "+cv.id.to_s unless val
        (val.classification_statistics!=nil) != (feature_type=="classification")
      end
      
      lmo = [ "found "+cvs.size.to_s+" crossvalidation/s for algorithm '"+algorithm.uri.to_s+"'" ]
      if cvs.size>0
        cvs_same_data = []
        cvs_other_data = []
        cvs.each do |cv|
          if cv.dataset_uri == model.metadata[OT.trainingDataset]
            cvs_same_data << cv
          else
            cvs_other_data << cv
          end
        end
        lmo << cvs_same_data.size.to_s+" crossvalidations/s where performed on the training dataset of the model ("+
          model.metadata[OT.trainingDataset].to_s+")"
        lmo << cvs_other_data.size.to_s+" crossvalidations/s where performed on the other datasets"        
        lmo << ""
        
        {cvs_same_data => "training dataset", cvs_other_data => "other datasets"}.each do |cvs,desc|
          next if cvs.size==0
          lmo << "crossvalidation/s on "+desc
          cvs.each do |cv|
            begin
              lmo << "crossvalidation: "+cv.crossvalidation_uri
              lmo << "dataset (see 9.3 Validation data): "+cv.dataset_uri
              val_datasets << cv.dataset_uri
              lmo << "settings: num-folds="+cv.num_folds.to_s+", random-seed="+cv.random_seed.to_s+", stratified:"+cv.stratified.to_s
  
              val  = YAML.load( OpenTox::RestClientWrapper.get(File.join(cv.crossvalidation_uri,"statistics"),{:subjectid => r.subjectid}) )
              case feature_type
              when "classification"
                lmo << "percent_correct: "+val[OT.classificationStatistics][OT.percentCorrect].to_s
                lmo << "weighted AUC: "+val[OT.classificationStatistics][OT.weightedAreaUnderRoc].to_s
              when "regression"
                lmo << "root_mean_squared_error: "+val[OT.regressionStatistics][OT.rootMeanSquaredError].to_s
                lmo << "r_square "+val[OT.regressionStatistics][OT.rSquare].to_s
              end
              reports = OpenTox::RestClientWrapper.get(File.join(CONFIG[:services]["opentox-validation"],
                "report/crossvalidation?crossvalidation_uris="+cv.crossvalidation_uri),{:subjectid => r.subjectid})
              if reports and reports.chomp.size>0
                lmo << "for more info see report: "+reports.split("\n")[0]
              else
                lmo << "for more info see report: not yet created for '"+cv.crossvalidation_uri+"'"
              end
            rescue => ex
              LOGGER.warn "could not add cv "+cv.crossvalidation_uri+" : "+ex.message            
            end
          end
          lmo << ""
        end
      end
   else
      lmo = [ "no prediction algortihm for model found, crossvalidation not possible" ]
    end
    r.qsar_robustness.lmo = lmo.to_html
    # "lmo" => "6.9", "yscrambling" => "6.10", "bootstrap" => "6.11", "other_statistics" => "6.12",

    LOGGER.debug "looking for validations with "+{:model_uri => model.uri}.inspect
    #vals = Lib::Validation.find(:all, :conditions => {:model_uri => model.uri})
    vals = Validation::Validation.find({:model_uri => model.uri})
    uniq_vals = []
    vals.each do |val|
      match = false
      uniq_vals.each do |val2|
        if val.test_dataset_uri == val2.test_dataset_uri
          match = true
          break
        end
      end
      uniq_vals << val unless match
    end
    
    r.qsar_predictivity = QsarPredictivity.new
    if uniq_vals.size > 0
      r.qsar_predictivity.validation_set_availability = "Yes"
      r.qsar_predictivity.validation_set_data = ValidationSetData.new(:chemname => "Yes", :cas => "Yes", 
        :smiles => "Yes", :inchi => "Yes", :mol => "Yes", :formula => "Yes")

      v = [ "found '"+uniq_vals.size.to_s+"' test-set validations of model '"+model.uri+"'" ]
      v << ""
      uniq_vals.each do |validation|
        v << "validation: "+validation.validation_uri
        v << "dataset (see 9.3 Validation data): "+validation.test_dataset_uri
        val_datasets << validation.test_dataset_uri
        case feature_type
        when "classification"
          v << "percent_correct: "+validation.classification_statistics[:percent_correct].to_s
          v << "average AUC: "+validation.classification_statistics[:average_area_under_roc].to_s
        when "regression"
          v << "root_mean_squared_error: "+validation.regression_statistics[:root_mean_squared_error].to_s
          v << "r_square "+validation.regression_statistics[:r_square].to_s
        end
        report = OpenTox::ValidationReport.find_for_validation(validation.validation_uri,r.subjectid)
        #reports = OpenTox::RestClientWrapper.get(File.join(CONFIG[:services]["opentox-validation"],
        #  "report/validation?validation_uris="+validation.validation_uri),{:subjectid => r.subjectid})
        if report
          v << "for more info see report: "+report.uri
        else
          v << "for more info see report: not yet created for '"+validation.validation_uri+"'"
        end
        v << ""
      end
    else
      v = [ "no validation for model '"+model.uri+"' found" ] 
    end
    r.qsar_predictivity.validation_predictivity = v.to_html
    task.progress(60) if task
    
    # chapter 7 
    # "validation_set_availability" => "7.1", "validation_set_data" => "7.2", "validation_set_descriptors" => "7.3", 
    # "validation_dependent_var_availability" => "7.4", "validation_other_info" => "7.5", "experimental_design" => "7.6", 
    # "validation_predictivity" => "7.7", "validation_assessment" => "7.8", "validation_comments" => "7.9", 
    task.progress(70) if task

    # chapter 8
    # "mechanistic_basis" => "8.1", "mechanistic_basis_comments" => "8.2", "mechanistic_basis_info" => "8.3",
    task.progress(80) if task
    
    # chapter 9
    # "comments" => "9.1", "bibliography" => "9.2", "attachments" => "9.3",
    
    r.qsar_miscellaneous = QsarMiscellaneous.new
    
    r.qsar_miscellaneous.attachment_training_data << AttachmentTrainingData.new( 
      { :description => training_dataset.title, 
        :filetype => "owl-dl", 
        :url => training_dataset.uri} ) if training_dataset
        
    val_datasets.each do |data_uri|
      if OpenTox::Dataset.exist?(data_uri, r.subjectid)
        d = OpenTox::Dataset.new(data_uri, r.subjectid)
        d.load_metadata( r.subjectid)
        r.qsar_miscellaneous.attachment_validation_data << AttachmentValidationData.new( 
          { :description => d.title, 
            :filetype => "owl-dl", 
            :url => data_uri} )
      end
    end
    task.progress(90) if task

    mysql_lite_retry do 
      r.save
    end
    task.progress(100) if task
  end
  
#  def self.get_report_content(type, id, *keys)
#    
#    report_content = get_report(type, id).get_content
#    keys.each do |k|
#      $sinatra.raise OpenTox::BadRequestError.new type+" unknown report property '#{key}'" unless report_content.is_a?(Hash) and report_content.has_key?(k)
#      report_content = report_content[k]
#    end
#    report_content    
#  end
  
  def self.get_report(type, id)
    report = nil
    mysql_lite_retry(3) do
      case type
      when /(?i)QMRF/
        report = ReachReports::QmrfReport.get(id)
      when /(?i)QPRF/
        report = ReachReports::QprfReport.get(id)
      end
      raise OpenTox::NotFoundError.new type+" report with id '#{id}' not found." unless report
    end
    return report
  end

  def self.delete_report(type, id, subjectid=nil)
    
    case type
    when /(?i)QMRF/
      report = ReachReports::QmrfReport.get(id)
    when /(?i)QPRF/
      report = ReachReports::QprfReport.get(id)
    end
    raise OpenTox::NotFoundError.new type+" report with id '#{id}' not found." unless report
    OpenTox::Authorization.delete_policies_from_uri(report.report_uri, subjectid) if subjectid
    return report.destroy
  end
  
end 
