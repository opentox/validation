
# = Reports::ReportContent
#
# wraps an xml-report, adds functionality for adding sections, adds a hash for tmp files
#
class Reports::ReportContent
  
  attr_accessor :xml_report, :tmp_files
  
  def initialize(title)
    @xml_report = Reports::XMLReport.new(title, Time.now.strftime("Created at %d.%m.%Y - %H:%M"))
    @tmp_file_count = 0
    @current_section = @xml_report.get_root_element
  end
  
  def add_section( section_title, section_text=nil )
    @current_section = @xml_report.add_section(@xml_report.get_root_element, section_title)
    @xml_report.add_paragraph(@current_section, section_text) if section_text
  end
  
  def end_section()
    @current_section = @xml_report.get_root_element
  end
  
  def add_warning(warning)
    sec = @xml_report.add_section(@current_section, "Warning")
    @xml_report.add_paragraph(sec, warning)
    end_section()
  end
  
  def add_paired_ttest_tables( validation_set,
                       group_attribute, 
                       test_attributes,
                       ttest_level = 0.9,
                       section_title = "Paired t-test",
                       section_text = nil)

    raise "no test_attributes given: "+test_attributes.inspect unless test_attributes.is_a?(Array) and test_attributes.size>0
    section_test = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_test, section_text) if section_text
        
    test_attributes.each do |test_attribute|         
      accept_values = validation_set.get_accept_values_for_attr(test_attribute)
      accept_values = [nil] unless accept_values and accept_values.size>0
      #puts "t-test for "+test_attribute.to_s+", class values: "+accept_values.to_s
      
      accept_values.each do |accept_value| 
        test_matrix = Reports::ReportStatisticalTest.test_matrix( validation_set.validations, 
          group_attribute, test_attribute, accept_value, "paired_ttest", ttest_level )
        #puts test_matrix.inspect
        titles = test_matrix[:titles]
        matrix = test_matrix[:matrix]
        table = []
        #puts titles.inspect
        table << [""] + titles
        titles.size.times do |i|
          table << [titles[i]] + matrix[i].collect{|v| (v==nil || v==0) ? "" : (v<0 ? "-" : "+") }
        end
        accept_value_str = accept_value!=nil ? " for class-value '"+accept_value.to_s+"'" : ""
        @xml_report.add_table(section_test, test_attribute.to_s+accept_value_str+", significance-level: "+ttest_level.to_s+", num results: "+
          test_matrix[:num_results].to_s, table, true, true)
      end
    end
  end
  
  def add_predictions( validation_set,
                        add_validation_uris,   
                        section_title="Predictions",
                        section_text=nil,
                        table_title="Predictions")
    section_table = @xml_report.add_section(@current_section, section_title)
    if validation_set.validations[0].get_predictions
      @xml_report.add_paragraph(section_table, section_text) if section_text
      v_uris = validation_set.validations.collect{|v| Array.new(v.num_instances.to_i,v.validation_uri)} if add_validation_uris
      @xml_report.add_table(section_table, table_title, Lib::OTPredictions.to_array(validation_set.validations.collect{|v| v.get_predictions}, 
        true, true, v_uris))
    else
      @xml_report.add_paragraph(section_table, "No prediction info available.")
    end
  end


  def add_result_overview( validation_set,
                        attribute_col,
                        attribute_row, 
                        attribute_values,
                        table_titles=nil,
                        section_title="Result overview",
                        section_text=nil )
    
    
    section_table = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_table, section_text) if section_text
    
    attribute_values.size.times do |i|
      attribute_val = attribute_values[i]
      table_title = table_titles ? table_titles[i] : "Result overview for "+attribute_val.to_s
      vals = validation_set.to_table( attribute_col, attribute_row, attribute_val)
      @xml_report.add_table(section_table, table_title, vals, true, true)  
    end
  end

  # result (could be transposed)
  #
  #  attr1      | attr2     | attr3
  #  ===========|===========|===========
  #  val1-attr1 |val1-attr2 |val1-attr3 
  #  val2-attr1 |val2-attr2 |val2-attr3
  #  val3-attr1 |val3-attr2 |val3-attr3
  #
  def add_result( validation_set, 
                        validation_attributes,
                        table_title,
                        section_title="Results",
                        section_text=nil)
                        #rem_equal_vals_attr=[])

    section_table = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_table, section_text) if section_text
    vals = validation_set.to_array(validation_attributes, true)
    vals = vals.collect{|a| a.collect{|v| v.to_s }}
    #PENDING transpose values if there more than 4 columns, and there are more than columns than rows
    transpose = vals[0].size>4 && vals[0].size>vals.size
    @xml_report.add_table(section_table, table_title, vals, !transpose, transpose, transpose)
  end
  
  def add_confusion_matrix(  validation, 
                                section_title="Confusion Matrix",
                                section_text=nil,
                                table_title="Confusion Matrix")
    section_confusion = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_confusion, section_text) if section_text
    @xml_report.add_table(section_confusion, table_title, 
      Reports::XMLReportUtil::create_confusion_matrix( validation.confusion_matrix ), true, true)
  end
  
  # bit of a hack to algin the last two plots in the report in to one row 
  def align_last_two_images( title )
    @xml_report.align_last_two_images(@current_section, title )
  end
  
  def add_regression_plot( validation_set,
                            name_attribute,
                            section_title="Regression Plot",
                            section_text=nil,
                            image_title="Regression Plot")
                            
    #section_regr = @xml_report.add_section(@current_section, section_title)
    section_regr = @current_section
    prediction_set = validation_set.collect{ |v| v.get_predictions }
        
    if prediction_set.size>0
      
      [true, false].each do |log|
        scale_str = (log ? " (logarithmic scale)" : " (linear scale)")
        image_title_2 = image_title + scale_str
        section_title_2 = section_title + scale_str
      
        section_text += "\nWARNING: regression plot information not available for all validation results" if prediction_set.size!=validation_set.size
        @xml_report.add_paragraph(section_regr, section_text) if section_text
        
        begin
          log_str = (log ? "_log" : "")
          plot_png = add_tmp_file("regr_plot"+log_str, "png")
          plot_svg = add_tmp_file("regr_plot"+log_str, "svg")
          omit_count = Reports::PlotFactory.create_regression_plot( [plot_png[:path], plot_svg[:path]], prediction_set, name_attribute, log )
          image_title_2 += " ("+omit_count.to_s+" datapoints omitted)" if omit_count>0
          @xml_report.add_imagefigure(section_regr, image_title_2,  plot_png[:name], "PNG", 100, plot_svg[:name])
        rescue Exception => ex
          LOGGER.error("Could not create regression plot: "+ex.message)
          rm_tmp_file(plot_png[:name])
          rm_tmp_file(plot_svg[:name])
          @xml_report.add_paragraph(section_regr, "could not create regression plot: "+ex.message)
        end  
      end
    else
      @xml_report.add_paragraph(section_regr, "No prediction info for regression available.")
    end
    align_last_two_images section_title+" in logarithmic and linear scale (values <= 0 are omitted in logarithmic scale)"
  end
  
  def add_train_test_plot( validation_set,
                           only_prediction_feature,
                           waiting_task,
                           section_title="Training Test Distribution Plot",
                           section_text=nil,
                           image_title=nil)
                            
    section_plot = @current_section
    prediction_set = validation_set.collect{ |v| v.get_predictions }
    @xml_report.add_paragraph(section_plot, section_text) if section_text
    
    begin
      plot_png = add_tmp_file("train_test_plot_#{only_prediction_feature}", "png")
      plot_svg = add_tmp_file("train_test_plot_#{only_prediction_feature}", "svg")
      omit_count = Reports::PlotFactory.create_train_test_plot( [plot_png[:path], plot_svg[:path]], 
        prediction_set, only_prediction_feature, waiting_task )
      unless image_title
        if only_prediction_feature
          image_title = "Prediction Feature: #{validation_set.validations.first.prediction_feature}"
        else
          image_title = "Features Excluding Prediction Feature"
        end
      end
      @xml_report.add_imagefigure(section_plot, image_title,  plot_png[:name], "PNG", 100, plot_svg[:name])
    rescue Exception => ex
      LOGGER.error("Could not create train test plot: "+ex.message)
      rm_tmp_file(plot_png[:name]) if plot_png
      rm_tmp_file(plot_svg[:name]) if plot_svg
      @xml_report.add_paragraph(section_plot, "could not create train test plot: "+ex.message)
    end  
        
  end
  
  def add_roc_plot( validation_set, 
                    accept_value, 
                    split_set_attribute=nil, 
                    image_title = nil, 
                    section_text="")
                            
    #section_roc = @xml_report.add_section(@current_section, section_title)
    section_roc = @current_section
    prediction_set = validation_set.collect{ |v| v.get_predictions && v.get_predictions.confidence_values_available? }
    image_title = "ROC Plot (true class is '"+accept_value.to_s+"')" unless image_title
    
    if prediction_set.size>0
      if prediction_set.size!=validation_set.size
        section_text += "\nWARNING: roc plot information not available for all validation results"
        LOGGER.error "WARNING: roc plot information not available for all validation results:\n"+
          "validation set size: "+validation_set.size.to_s+", prediction set size: "+prediction_set.size.to_s
      end
      @xml_report.add_paragraph(section_roc, section_text) if section_text
      begin
        plot_png = add_tmp_file("roc_plot", "png")
        plot_svg = add_tmp_file("roc_plot", "svg")
        Reports::PlotFactory.create_roc_plot( [plot_png[:path], plot_svg[:path]], prediction_set, accept_value, split_set_attribute )#prediction_set.size>1 )
        @xml_report.add_imagefigure(section_roc, image_title, plot_png[:name], "PNG", 100, plot_svg[:name])
      rescue Exception => ex
        msg = "WARNING could not create roc plot for class value '"+accept_value.to_s+"': "+ex.message
        LOGGER.error(msg)
        rm_tmp_file(plot_png[:name])
        rm_tmp_file(plot_svg[:name])
        @xml_report.add_paragraph(section_roc, msg)
      end  
    else
      @xml_report.add_paragraph(section_roc, "No prediction-confidence info for roc plot available.")
    end
    
  end
  
  def add_confidence_plot( validation_set,
                            performance_attribute,
                            performance_accept_value,
                            split_set_attribute = nil,
                            image_title = "Confidence Plot",
                            section_text="")
                            
    #section_conf = @xml_report.add_section(@current_section, section_title)
    section_conf = @current_section
    prediction_set = validation_set.collect{ |v| v.get_predictions && v.get_predictions.confidence_values_available? }
        
    if prediction_set.size>0
      if prediction_set.size!=validation_set.size
        section_text += "\nWARNING: plot information not available for all validation results"
        LOGGER.error "WARNING: plot information not available for all validation results:\n"+
          "validation set size: "+validation_set.size.to_s+", prediction set size: "+prediction_set.size.to_s
      end
      @xml_report.add_paragraph(section_conf, section_text) if section_text and section_text.size>0
      
      begin
        plot_png = add_tmp_file("conf_plot", "png")
        plot_svg = add_tmp_file("conf_plot", "svg")
        Reports::PlotFactory.create_confidence_plot( [plot_png[:path], plot_svg[:path]], prediction_set, performance_attribute, 
          performance_accept_value, split_set_attribute, false )
        @xml_report.add_imagefigure(section_conf, image_title, plot_png[:name], "PNG", 100, plot_svg[:name])
      rescue Exception => ex
        msg = "WARNING could not create confidence plot: "+ex.message
        LOGGER.error(msg)
        rm_tmp_file(plot_png[:name])
        rm_tmp_file(plot_svg[:name])
        @xml_report.add_paragraph(section_conf, msg)
      end   
    else
      @xml_report.add_paragraph(section_conf, "No prediction-confidence info for confidence plot available.")
    end
  end
  
  def add_ranking_plots( validation_set,
                            compare_attribute,
                            equal_attribute,
                            rank_attributes,
                            section_title="Ranking Plots",
                            section_text="This section contains the ranking plots.")
    
    section_rank = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_rank, section_text) if section_text
    
    rank_attributes.each do |a|
      add_ranking_plot(section_rank, validation_set, compare_attribute, equal_attribute, a)
    end
  end
  
  def add_ranking_plot( report_section, 
                        validation_set,
                        compare_attribute,
                        equal_attribute,
                        rank_attribute,
                        image_titles=nil,
                        image_captions=nil)

    accept_values = validation_set.get_class_values_for(rank_attribute)
    puts "ranking plot for "+rank_attribute.to_s+", class values: "+accept_values.to_s
    
    accept_values.size.times do |i|  
      class_value = accept_values[i]
      if image_titles
        image_title = image_titles[i]
      else
        if class_value!=nil
          image_title = rank_attribute.to_s+" Ranking Plot for class-value '"+class_value.to_s+"'"
        else 
          image_title = rank_attribute.to_s+" Ranking Plot"
        end
      end
      image_caption = image_captions ? image_captions[i] : nil
      plot_file_name = "ranking_plot"+@tmp_file_count.to_s+".svg"
      @tmp_file_count += 1
      plot_file_path = add_tmp_file(plot_file_name)
      Reports::PlotFactory::create_ranking_plot(plot_file_path, validation_set, compare_attribute, equal_attribute, rank_attribute, class_value)
      @xml_report.add_imagefigure(report_section, image_title, plot_file_name, "SVG", 75, image_caption)
    end
  end
  
  def add_bar_plot(validation_set,
                            title_attribute,
                            value_attributes,
                            section_title="Bar Plot",
                            section_text=nil,
                            image_title="Bar Plot")
    
    section_bar = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_bar, section_text) if section_text
    plot_png = add_tmp_file("bar_plot", "png")
    plot_svg = add_tmp_file("bar_plot", "svg")
    Reports::PlotFactory.create_bar_plot([plot_png[:path], plot_svg[:path]], validation_set, title_attribute, value_attributes )
    @xml_report.add_imagefigure(section_bar, image_title, plot_png[:name], "PNG", 100, plot_svg[:name])
  end  
  
  def add_box_plot(validation_set,
                   title_attribute,
                   value_attributes,
                   section_title="Boxplots",
                   section_text=nil)
    
    section_box = @xml_report.add_section(@current_section, section_title)
    @xml_report.add_paragraph(section_box, section_text) if section_text
    
    plot_png = nil; plot_svg = nil
    begin
      plot_input = []
      value_attributes.each do |a|
        accept = validation_set.get_accept_values_for_attr(a)
        if accept and accept.size>0
          accept.each do |c|
            title = a.to_s.gsub("_","-") + ( (accept.size==1 || c==nil) ? "" : "("+c.to_s+")" )
            plot_input << [a,c,title]
          end
        else
          plot_input << [a,nil,a.to_s.gsub("_","-")]
        end  
      end
      
      i = 0
      figs = []
      plot_input.each do |attrib,class_value,image_title|
        plot_png = add_tmp_file("box_plot#{i}", "png")
        plot_svg = add_tmp_file("box_plot#{i}", "svg")      
        Reports::PlotFactory.create_box_plot([plot_png[:path], plot_svg[:path]], 
           validation_set, title_attribute, attrib, class_value )
        figs << @xml_report.imagefigure(image_title, plot_png[:name],
           "PNG", 50, plot_svg[:name])
        plot_png = nil; plot_svg = nil
        i += 1
      end
      
      i = 1
      figs.each_slice(4) do |f| 
        @xml_report.add_imagefigures_in_row(section_box,f,"Boxplots #{i}")
        i+=1
      end
    rescue Exception => ex
      msg = "WARNING could not create box plot: "+ex.message
      LOGGER.error(msg)
      rm_tmp_file(plot_png[:name]) if plot_png
      rm_tmp_file(plot_svg[:name]) if plot_svg
      @xml_report.add_paragraph(section_box, msg)
    end   
  end  
  
  private
  def add_tmp_file(name, extension)
    tmp_file_name = name.to_s+@tmp_file_count.to_s+"."+extension.to_s
    @tmp_file_count += 1
    @tmp_files = {} unless @tmp_files
    raise "file name already exits" if @tmp_files[tmp_file_name] || (@text_files && @text_files[tmp_file_name])  
    tmp_file_path = Reports::Util.create_tmp_file(tmp_file_name)
    @tmp_files[tmp_file_name] = tmp_file_path
    return {:name => tmp_file_name, :path => tmp_file_path}
  end
  
  def rm_tmp_file(tmp_file_name)
    @tmp_files.delete(tmp_file_name) if @tmp_files.has_key?(tmp_file_name)
  end
  
end