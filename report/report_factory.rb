
# selected attributes of interest when generating the report for a train-/test-evaluation                      
VAL_ATTR_TRAIN_TEST = [ :model_uri, :training_dataset_uri, :test_dataset_uri, :prediction_feature ]
# selected attributes of interest when generating the crossvalidation report
VAL_ATTR_CV = [ :algorithm_uri, :dataset_uri, :num_folds, :crossvalidation_fold ]

# selected attributes of interest when performing classification
VAL_ATTR_CLASS = [ :num_instances, :num_unpredicted, :accuracy, :weighted_accuracy, :average_area_under_roc,
  :area_under_roc, :f_measure, :true_positive_rate, :true_negative_rate, :positive_predictive_value, :negative_predictive_value ]
VAL_ATTR_REGR = [ :num_instances, :num_unpredicted, :root_mean_squared_error, 
  :weighted_root_mean_squared_error, :mean_absolute_error, :weighted_mean_absolute_error, :r_square, :weighted_r_square,
  :sample_correlation_coefficient ]

#VAL_ATTR_BOX_PLOT_CLASS = [ :accuracy, :average_area_under_roc, 
#  :area_under_roc, :f_measure, :true_positive_rate, :true_negative_rate ]
VAL_ATTR_BOX_PLOT_CLASS = [ :accuracy, :area_under_roc, :f_measure, :true_positive_rate, :true_negative_rate, :positive_predictive_value, :negative_predictive_value ]
VAL_ATTR_BOX_PLOT_REGR = [ :root_mean_squared_error, :mean_absolute_error, :r_square ]

VAL_ATTR_TTEST_REGR = [ :r_square, :root_mean_squared_error ]
VAL_ATTR_TTEST_CLASS = [ :accuracy, :average_area_under_roc ]


# = Reports::ReportFactory 
#
# creates various reports (Reports::ReportContent) 
#
module Reports::ReportFactory
  
  RT_VALIDATION = "validation"
  RT_CV = "crossvalidation"
  RT_ALG_COMP = "algorithm_comparison"
  RT_METHOD_COMP = "method_comparison"
  
  REPORT_TYPES = [RT_VALIDATION, RT_CV, RT_ALG_COMP, RT_METHOD_COMP ]
  
  # creates a report of a certain type according to the validation data in validation_set 
  #
  # call-seq:
  #   self.create_report(type, validation_set) => Reports::ReportContent
  #
  def self.create_report(type, validation_set, params={}, task=nil)
    case type
    when RT_VALIDATION
      create_report_validation(validation_set, {}, task)
    when RT_CV
      create_report_crossvalidation(validation_set, {}, task)
    when RT_ALG_COMP
      create_report_compare_algorithms(validation_set, params, task)
    when RT_METHOD_COMP
      create_report_compare_methods(validation_set, params, task)      
    else
      raise "unknown report type "+type.to_s
    end
  end
  
  private
  # this function is only to set task progress accordingly
  # loading predicitons is time consuming, and is done dynamically ->  
  # pre-load and set task progress
  def self.pre_load_predictions( validation_set, task=nil)
    i = 0
    task_step = 100 / validation_set.size.to_f
    validation_set.validations.each do |v|
      v.get_predictions( OpenTox::SubTask.create(task, i*task_step, (i+1)*task_step ) )
      i += 1
    end
  end
  
  def self.add_filter_warning(report, filter_params)
    msg = "The validation results for this report have been filtered."
    msg += " Minimum confidence: "+ filter_params[:min_confidence].to_s if 
      filter_params[:min_confidence]!=nil 
    msg += " Minimum number of predictions (sorted with confidence): "+ filter_params[:min_num_predictions].to_s if 
      filter_params[:min_num_predictions]!=nil 
    msg += " Maximum number of predictions: "+ filter_params[:max_num_predictions].to_s if 
      filter_params[:max_num_predictions]!=nil 
    report.add_warning(msg)      
  end
  
  def self.create_report_validation(validation_set, params, task=nil)
    
    raise OpenTox::BadRequestError.new("num validations is not equal to 1") unless validation_set.size==1
    val = validation_set.validations[0]
    pre_load_predictions( validation_set, OpenTox::SubTask.create(task,0,50) )

    report = Reports::ReportContent.new("Validation report")
    add_filter_warning(report, validation_set.filter_params) if validation_set.filter_params!=nil
  
    case val.feature_type
    when "classification"
      report.add_result(validation_set, [:validation_uri] + VAL_ATTR_TRAIN_TEST + VAL_ATTR_CLASS, "Results", "Results")
      report.add_confusion_matrix(val)
      report.add_section("Plots")
      if (validation_set.get_accept_values.size == 2)
        if validation_set.get_true_accept_value!=nil
          report.add_roc_plot(validation_set, validation_set.get_true_accept_value)
        else
          report.add_roc_plot(validation_set, validation_set.get_accept_values[0])
          report.add_roc_plot(validation_set, validation_set.get_accept_values[1])
          report.align_last_two_images "ROC Plots"
        end
      end
      report.add_confidence_plot(validation_set, :accuracy, nil)
      validation_set.get_accept_values.each do |accept_value|
        report.add_confidence_plot(validation_set, :true_positive_rate, accept_value)
        report.add_confidence_plot(validation_set, :positive_predictive_value, accept_value)
        report.align_last_two_images "Confidence Plots"
      end
    when "regression"
      report.add_result(validation_set, [:validation_uri] + VAL_ATTR_TRAIN_TEST + VAL_ATTR_REGR, "Results", "Results")
      report.add_section("Plots")
      report.add_regression_plot(validation_set, :model_uri)
      report.add_confidence_plot(validation_set, :root_mean_squared_error, nil)
      report.add_confidence_plot(validation_set, :r_square, nil)
      report.align_last_two_images "Confidence Plots"
    end
    task.progress(70) if task
    report.add_train_test_plot( validation_set, false, OpenTox::SubTask.create(task,70,80) )
    report.add_train_test_plot( validation_set, true, OpenTox::SubTask.create(task,80,90) )
    report.align_last_two_images "Training Test Data Distribution Plots"
    report.end_section

    report.add_result(validation_set, Validation::ALL_PROPS, "All Results", "All Results")
    report.add_predictions( validation_set )
    task.progress(100) if task
    report
  end
  
  def self.create_report_crossvalidation(validation_set, params, task=nil)
    
    raise OpenTox::BadRequestError.new "cv report not implemented for filter params" if validation_set.filter_params!=nil
    raise OpenTox::BadRequestError.new("num validations is not >1") unless validation_set.size>1
    raise OpenTox::BadRequestError.new("crossvalidation-id not unique and != nil: "+
      validation_set.get_values(:crossvalidation_id,false).inspect) if validation_set.unique_value(:crossvalidation_id)==nil
    validation_set.load_cv_attributes
    raise OpenTox::BadRequestError.new("num validations ("+validation_set.size.to_s+") is not equal to num folds ("+
      validation_set.unique_value(:num_folds).to_s+")") unless validation_set.unique_value(:num_folds).to_i==validation_set.size
    raise OpenTox::BadRequestError.new("num different folds is not equal to num validations") unless validation_set.num_different_values(:crossvalidation_fold)==validation_set.size
    raise OpenTox::BadRequestError.new("validations must have unique feature type, i.e. must be either all regression, "+
      "or all classification validations") unless validation_set.unique_feature_type
    pre_load_predictions( validation_set, OpenTox::SubTask.create(task,0,80) )
    validation_set.validations.sort! do |x,y|
      x.crossvalidation_fold.to_f <=> y.crossvalidation_fold.to_f
    end
    cv_set = validation_set.replace_with_cv_stats
    raise unless cv_set.size==1
    
    #puts cv_set.get_values(:percent_correct_variance, false).inspect
    report = Reports::ReportContent.new("Crossvalidation report")
    res_titel = "Crossvalidation Results"
    res_text = "These performance statistics have been derieved by accumulating all predictions on the various fold (i.e. these numbers are NOT averaged results over all crossvalidation folds)."
    
    case validation_set.unique_feature_type
    when "classification"
      report.add_result(cv_set, [:crossvalidation_uri]+VAL_ATTR_CV+VAL_ATTR_CLASS-[:crossvalidation_fold], res_titel, res_titel, res_text)
      report.add_confusion_matrix(cv_set.validations[0])
      report.add_section("Plots")
      [nil, :crossvalidation_fold].each do |split_attribute|
        if (validation_set.get_accept_values.size == 2)
          if validation_set.get_true_accept_value!=nil
            report.add_roc_plot(validation_set, validation_set.get_true_accept_value,split_attribute)
          else
            report.add_roc_plot(validation_set, validation_set.get_accept_values[0], split_attribute)
            report.add_roc_plot(validation_set, validation_set.get_accept_values[1], split_attribute)
            report.align_last_two_images "ROC Plots"
          end
        end
        report.add_confidence_plot(validation_set,:accuracy,nil,split_attribute)
        validation_set.get_accept_values.each do |accept_value|
          report.add_confidence_plot(validation_set, :true_positive_rate, accept_value, split_attribute)
          report.add_confidence_plot(validation_set, :positive_predictive_value, accept_value, split_attribute)
          report.align_last_two_images "Confidence Plots"
        end
      end
      report.end_section
      report.add_result(validation_set, 
        [:validation_uri, :validation_report_uri]+VAL_ATTR_CV+VAL_ATTR_CLASS-[:num_folds, :dataset_uri, :algorithm_uri],
        "Results","Results") if 
        (cv_set.unique_value(:num_folds).to_i < cv_set.unique_value(:num_instances).to_i)
    when "regression"
      report.add_result(cv_set, [:crossvalidation_uri]+VAL_ATTR_CV+VAL_ATTR_REGR-[:crossvalidation_fold],res_titel, res_titel, res_text)
      report.add_section("Plots")
      report.add_regression_plot(validation_set, :crossvalidation_fold)
      report.add_confidence_plot(validation_set, :root_mean_squared_error, nil)
      report.add_confidence_plot(validation_set, :r_square, nil)
      report.align_last_two_images "Confidence Plots"
      report.add_confidence_plot(validation_set, :root_mean_squared_error, nil, :crossvalidation_fold)
      report.add_confidence_plot(validation_set, :r_square, nil, :crossvalidation_fold)
      report.align_last_two_images "Confidence Plots Across Folds"
      report.end_section
      report.add_result(validation_set, 
        [:validation_uri, :validation_report_uri]+VAL_ATTR_CV+VAL_ATTR_REGR-[:num_folds, :dataset_uri, :algorithm_uri], 
        "Results","Results") if 
        (cv_set.unique_value(:num_folds).to_i < cv_set.unique_value(:num_instances).to_i)
    end
    task.progress(90) if task
      
    report.add_result(validation_set, Validation::ALL_PROPS, "All Results", "All Results") if
      (cv_set.unique_value(:num_folds).to_i < cv_set.unique_value(:num_instances).to_i)
    report.add_predictions( validation_set ) #, [:crossvalidation_fold] )
    task.progress(100) if task
    report
  end
  
  def self.create_report_compare_algorithms(validation_set, params={}, task=nil)
    
    #validation_set.to_array([:test_dataset_uri, :model_uri, :algorithm_uri], false).each{|a| puts a.inspect}
    raise OpenTox::BadRequestError.new("num validations is not >1") unless validation_set.size>1
    raise OpenTox::BadRequestError.new("validations must have unique feature type, i.e. must be either all regression, "+
      "or all classification validations") unless validation_set.unique_feature_type
    raise OpenTox::BadRequestError.new("number of different identifiers <2: "+
      validation_set.get_values(:identifier).inspect) if validation_set.num_different_values(:identifier)<2
      
    if validation_set.has_nil_values?(:crossvalidation_id)
      raise OpenTox::BadRequestError.new("algorithm comparison for non crossvalidation not yet implemented")
    else
      raise OpenTox::BadRequestError.new("num different cross-validation-ids <2") if validation_set.num_different_values(:crossvalidation_id)<2
      validation_set.load_cv_attributes
      compare_algorithms_crossvalidation(validation_set, params, task)
    end
  end  
  
  # create Algorithm Comparison report
  # crossvalidations, 1-n datasets, 2-n algorithms
  def self.compare_algorithms_crossvalidation(validation_set, params={}, task=nil)
    
    # groups results into sets with equal dataset 
    if (validation_set.num_different_values(:dataset_uri)>1)
      LOGGER.debug "compare report -- num different datasets: "+validation_set.num_different_values(:dataset_uri).to_s
      dataset_grouping = Reports::Util.group(validation_set.validations, [:dataset_uri])
      # check if equal values in each group exist
      Reports::Util.check_group_matching(dataset_grouping, [:crossvalidation_fold, :num_folds, :stratified, :random_seed])
    else
      dataset_grouping = [ validation_set.validations ]
    end
    
    # we only checked that equal validations exist in each dataset group, now check for each identifier
    dataset_grouping.each do |validations|
      algorithm_grouping = Reports::Util.group(validations, [:identifier])
      Reports::Util.check_group_matching(algorithm_grouping, [:crossvalidation_fold, :num_folds, :stratified, :random_seed])
    end
    
    pre_load_predictions( validation_set, OpenTox::SubTask.create(task,0,80) )
    report = Reports::ReportContent.new("Algorithm comparison report")
    add_filter_warning(report, validation_set.filter_params) if validation_set.filter_params!=nil
    
    if (validation_set.num_different_values(:dataset_uri)>1)
      all_merged = validation_set.merge([:algorithm_uri, :dataset_uri, :crossvalidation_id, :crossvalidation_uri])
      report.add_ranking_plots(all_merged, :algorithm_uri, :dataset_uri,
        [:percent_correct, :average_area_under_roc, :true_positive_rate, :true_negative_rate] )
      report.add_result_overview(all_merged, :algorithm_uri, :dataset_uri, [:percent_correct, :average_area_under_roc, :true_positive_rate, :true_negative_rate])
    end
      
    result_attributes = [:identifier,:crossvalidation_uri,:crossvalidation_report_uri]+VAL_ATTR_CV-[:crossvalidation_fold,:num_folds,:dataset_uri]
    case validation_set.unique_feature_type
    when "classification"
      result_attributes += VAL_ATTR_CLASS
      ttest_attributes = VAL_ATTR_TTEST_CLASS
      box_plot_attributes = VAL_ATTR_BOX_PLOT_CLASS
    else 
      result_attributes += VAL_ATTR_REGR
      ttest_attributes = VAL_ATTR_TTEST_REGR
      box_plot_attributes = VAL_ATTR_BOX_PLOT_REGR
    end
    
    if params[:ttest_attributes] and params[:ttest_attributes].chomp.size>0
      ttest_attributes = params[:ttest_attributes].split(",").collect{|a| a.to_sym}
    end
    ttest_significance = 0.9
    if params[:ttest_significance]
      ttest_significance = params[:ttest_significance].to_f
    end
    
    box_plot_attributes += ttest_attributes
    box_plot_attributes.uniq!
    
    result_attributes += ttest_attributes
    result_attributes.uniq!
      
    dataset_grouping.each do |validations|
    
      set = Reports::ValidationSet.create(validations)
      
      dataset = validations[0].dataset_uri
      merged = set.merge([:identifier, :dataset_uri]) #, :crossvalidation_id, :crossvalidation_uri])
      merged.sort(:identifier)
      
      merged.validations.each do |v|
        v.crossvalidation_uri = v.crossvalidation_uri.split(";").uniq.join(" ")
        v.crossvalidation_report_uri = v.crossvalidation_report_uri.split(";").uniq.join(" ") if  v.crossvalidation_report_uri
      end
      
      report.add_section("Dataset: "+dataset)
      res_titel = "Average Results on Folds"
      res_text = "These performance statistics have been derieved by computing the mean of the statistics on each crossvalidation fold."
      report.add_result(merged,result_attributes,res_titel,res_titel,res_text)
      # pending: regression stats have different scales!!!
      report.add_box_plot(set, :identifier, box_plot_attributes)
      report.add_paired_ttest_tables(set, :identifier, ttest_attributes, ttest_significance) if ttest_significance>0
      report.end_section
    end
    task.progress(100) if task
    report
  end
  
  def self.create_report_compare_methods(validation_set, params={}, task=nil)
    raise OpenTox::BadRequestError.new("num validations is not >1") unless validation_set.size>1
    raise OpenTox::BadRequestError.new("validations must have unique feature type, i.e. must be either all regression, "+
      "or all classification validations") unless validation_set.unique_feature_type
    raise OpenTox::BadRequestError.new("number of different identifiers <2: "+
      validation_set.get_values(:identifier).inspect) if validation_set.num_different_values(:identifier)<2
    #validation_set.load_cv_attributes
    
    pre_load_predictions( validation_set, OpenTox::SubTask.create(task,0,80) )
    report = Reports::ReportContent.new("Method comparison report")
    add_filter_warning(report, validation_set.filter_params) if validation_set.filter_params!=nil
    
    result_attributes = [:identifier,:validation_uri,:validation_report_uri]+VAL_ATTR_CV-[:crossvalidation_fold,:num_folds,:dataset_uri]
    case validation_set.unique_feature_type
    when "classification"
      result_attributes += VAL_ATTR_CLASS
      box_plot_attributes = VAL_ATTR_BOX_PLOT_CLASS
    else 
      result_attributes += VAL_ATTR_REGR
      box_plot_attributes = VAL_ATTR_BOX_PLOT_REGR
    end
    
    merged = validation_set.merge([:identifier])
    merged.sort(:identifier)
    
    merged.validations.each do |v|
      v.validation_uri = v.validation_uri.split(";").uniq.join(" ")
      v.validation_report_uri = v.validation_report_uri.split(";").uniq.join(" ") if  v.validation_report_uri
    end
      
    msg = merged.validations.collect{|v| v.identifier+" ("+Lib::MergeObjects.merge_count(v).to_s+"x)"}.join(", ")
    report.add_result(merged,result_attributes,"Average Results","Results",msg)
    
    report.add_box_plot(validation_set, :identifier, box_plot_attributes)
    report
  end

end

