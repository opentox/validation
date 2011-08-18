ENV['JAVA_HOME'] = "/usr/bin" unless ENV['JAVA_HOME']
ENV['PATH'] = ENV['JAVA_HOME']+":"+ENV['PATH'] unless ENV['PATH'].split(":").index(ENV['JAVA_HOME'])
ENV['RANK_PLOTTER_JAR'] = "RankPlotter/RankPlotter.jar" unless ENV['RANK_PLOTTER_JAR']

class Array
  def swap!(i,j)
    tmp = self[i]
    self[i] = self[j]
    self[j] = tmp
  end
  
  # summing up values of fields where array __groups__ has equal values
  # EXAMPLE
  # self:       [1,    0,  1,  2,  3,  0, 2]
  # __groups__: [100, 90, 70, 70, 30, 10, 0]
  # returns:
  # [ 1, 0, 3, 3, 0, 2]
  # (fields with equal value 70 are compressed)
  # PRECONDITION
  # __groups__ has to be sorted
  def compress_sum(groups)
    compress(groups) do |a,b|
      a+b
    end
  end
  
  # see compress_sum, replace sum with max
  def compress_max(groups)
    compress(groups) do |a,b|
      a > b ? a : b
    end
  end
  
  private
  def compress(groups)
    raise "length not equal" unless self.size==groups.size
    raise "to small" unless self.size>=2
    a = [ self[0] ]
    (1..groups.size-1).each do |i|
      if groups[i]!=groups[i-1]
        a << self[i]
      else
        a[-1] = yield a[-1],self[i]
      end
    end
    a
  end
end


module Reports
  
  module PlotFactory
    
    def self.create_regression_plot( out_files, validation_set, name_attribute, logscale=true )
      
      out_files = [out_files] unless out_files.is_a?(Array)
      LOGGER.debug "Creating regression plot, out-file:"+out_files.to_s
      
      omit_count = 0
      names = []
      x = []
      y = []
      validation_set.validations.each do |v|
        x_i = v.get_predictions.predicted_values
        y_i = v.get_predictions.actual_values
        
        # filter out nil-predictions and <=0 predictions if log-scale wanted
        valid_indices = []
        x_i.size.times do |i|
          if x_i[i]!=nil and y_i[i]!=nil
            if !logscale or (x_i[i]>0 and y_i[i]>0)
              valid_indices << i 
            else
              omit_count += 1
            end
          end
        end
        if valid_indices.size < x_i.size
          x_i = valid_indices.collect{ |i| x_i[i] }
          y_i = valid_indices.collect{ |i| y_i[i] }
        end

        names << ( name_attribute==:crossvalidation_fold ? "fold " : "" ) + v.send(name_attribute).to_s
        x << x_i
        y << y_i
      end
      names = [""] if names.size==1 

      omit_str = omit_count>0 ? " ("+omit_count.to_s+" predictions omitted)" : ""
      raise "no predictions performed"+omit_str if x.size==0 || x[0].size==0
      out_files.each do |out_file|
        RubyPlot::regression_point_plot(out_file, "Regression plot", "Predicted values", "Actual values", names, x, y, logscale)
      end
      omit_count
    end
    
    
    # creates a roc plot (result is plotted into out_file)
    # * if (split_set_attributes == nil?)
    #   * the predictions of all validations in the validation set are plotted as one average roc-curve
    #   * if (show_single_curves == true) -> the single predictions of each validation are plotted as well   
    # * if (split_set_attributes != nil?)
    #   * the validation set is splitted into sets of validation_sets with equal attribute values
    #   * each of theses validation sets is plotted as a roc-curve  
    #
    def self.create_roc_plot( out_files, validation_set, class_value, split_set_attribute=nil,
        x_label="False positive rate", y_label="True Positive Rate" )
      
      out_files = [out_files] unless out_files.is_a?(Array)
      LOGGER.debug "creating roc plot for '"+validation_set.size.to_s+"' validations, out-files:"+out_files.inspect
      
      data = []
      if split_set_attribute
        attribute_values = validation_set.get_values(split_set_attribute)
        attribute_values.each do |value|
          begin
            data << transform_roc_predictions(validation_set.filter({split_set_attribute => value}), class_value, false )
            data[-1].name = split_set_attribute.to_s.nice_attr+" "+value.to_s
          rescue
            LOGGER.warn "could not create ROC plot for "+value.to_s
          end
        end
      else
        data << transform_roc_predictions(validation_set, class_value )
      end  
      
      out_files.each do |out_file|
        RubyPlot::plot_lines(out_file, "ROC-Plot", x_label, y_label, data )
      end
    end
    
    
    def self.create_confidence_plot( out_files, validation_set, class_value, split_set_attribute=nil, show_single_curves=false )
      
      out_files = [out_files] unless out_files.is_a?(Array)
      LOGGER.debug "creating confidence plot for '"+validation_set.size.to_s+"' validations, out-file:"+out_files.inspect
      
      if split_set_attribute
        attribute_values = validation_set.get_values(split_set_attribute)
        names = []
        confidence = []
        performance = []
        attribute_values.each do |value|
          begin
            data = transform_confidence_predictions(validation_set.filter({split_set_attribute => value}), class_value, false)
            names << split_set_attribute.to_s.nice_attr+" "+value.to_s
            confidence << data[:confidence][0]
            performance << data[:performance][0]
          rescue
            LOGGER.warn "could not create confidence plot for "+value.to_s
          end
        end
        #RubyPlot::plot_lines(out_file, "Percent Correct vs Confidence Plot", "Confidence", "Percent Correct", names, fp_rates, tp_rates )
        out_files.each do |out_file|
          case validation_set.unique_feature_type
          when "classification"
            RubyPlot::accuracy_confidence_plot(out_file, "Percent Correct vs Confidence Plot", "Confidence", "Percent Correct", names, confidence, performance)
          when "regression"
            RubyPlot::accuracy_confidence_plot(out_file, "RMSE vs Confidence Plot", "Confidence", "RMSE", names, confidence, performance, true)
          end
        end
      else
        data = transform_confidence_predictions(validation_set, class_value, show_single_curves)
        out_files.each do |out_file|
          case validation_set.unique_feature_type
          when "classification"
            RubyPlot::accuracy_confidence_plot(out_file, "Percent Correct vs Confidence Plot", "Confidence", "Percent Correct", data[:names], data[:confidence], data[:performance])
          when "regression"
            RubyPlot::accuracy_confidence_plot(out_file, "RMSE vs Confidence Plot", "Confidence", "RMSE", data[:names], data[:confidence], data[:performance], true)
          end
        end
      end  
    end
    
    
    def self.create_bar_plot( out_files, validation_set, title_attribute, value_attributes )
  
      out_files = [out_files] unless out_files.is_a?(Array)
      LOGGER.debug "creating bar plot, out-files:"+out_files.inspect
      
      data = []
      titles = []
      labels = []
      
      validation_set.validations.each do |v|
        values = []
        value_attributes.each do |a|
          
          accept = validation_set.get_accept_values_for_attr(a)
          if accept and accept.size>0
            accept.each do |class_value|
              value = v.send(a)
              if value.is_a?(Hash)
                if class_value==nil
                  avg_value = 0
                  value.values.each{ |val| avg_value+=val }
                  value = avg_value/value.values.size.to_f
                else
                  raise "bar plot value is hash, but no entry for class-value ("+class_value.to_s+"); value for "+a.to_s+" -> "+value.inspect unless value.key?(class_value)
                  value = value[class_value]
                end
              end
              raise "value is nil\nattribute: "+a.to_s+"\nvalidation: "+v.inspect if value==nil
              values.push(value)
              labels.push(a.to_s.gsub("_","-") + ( class_value==nil ? "" : "("+class_value.to_s+")" ))
            end
          else
            value = v.send(a)
            values.push(value)
            labels.push(a.to_s.gsub("_","-"))
          end
          
        end
        
        titles << v.send(title_attribute).to_s
        raise "no title for '"+title_attribute.to_s+"' in validation: "+v.to_yaml if titles[-1].to_s.size==0
        data << values
      end
      
      titles = titles.remove_common_prefix
      (0..titles.size-1).each do |i|
        data[i] = [titles[i]] + data[i]
      end
      
      LOGGER.debug "bar plot labels: "+labels.inspect 
      LOGGER.debug "bar plot data: "+data.inspect
      
      out_files.each do |out_file|
        RubyPlot::plot_bars('Bar plot', labels, data, out_file)
      end
    end
    
    
    def self.create_ranking_plot( out_file, validation_set, compare_attribute, equal_attribute, rank_attribute, class_value=nil )

      #compute ranks
      #puts "rank attibute is "+rank_attribute.to_s
      
      rank_set = validation_set.compute_ranking([equal_attribute],rank_attribute,class_value)
      #puts compare_attribute
      #puts rank_set.to_array([:algorithm_uri, :dataset_uri, :percent_correct, :percent_correct_ranking]).collect{|a| a.inspect}.join("\n")
      #puts "\n"
      
      #compute avg ranks
      merge_set = rank_set.merge([compare_attribute])
      #puts merge_set.to_array([:algorithm_uri, :dataset_uri, :percent_correct, :percent_correct_ranking]).collect{|a| a.inspect}.join("\n")
      
      
      comparables = merge_set.get_values(compare_attribute)
      ranks = merge_set.get_values((rank_attribute.to_s+"_ranking").to_sym,false)
      
      plot_ranking( rank_attribute.to_s+" ranking",
                    comparables, 
                    ranks, 
                    nil, #0.1, 
                    validation_set.num_different_values(equal_attribute), 
                    out_file) 
    end
  
    protected
    def self.plot_ranking( title, comparables_array, ranks_array, confidence = nil, numdatasets = nil, out_file = nil )
      
      (confidence and numdatasets) ? conf = "-q "+confidence.to_s+" -k "+numdatasets.to_s : conf = ""
      out_file ? show = "-o" : show = ""  
      (title and title.length > 0) ? tit = '-t "'+title+'"' : tit = ""  
      #title = "-t \""+ranking_value_prop+"-Ranking ("+comparables.size.to_s+" "+comparable_prop+"s, "+num_groups.to_s+" "+ranking_group_prop+"s, p < "+p.to_s+")\" "
      
      cmd = "java -jar "+ENV['RANK_PLOTTER_JAR']+" "+tit+" -c '"+
        comparables_array.join(",")+"' -r '"+ranks_array.join(",")+"' "+conf+" "+show #+" > /home/martin/tmp/test.svg" 
      #puts "\nplotting: "+cmd
      LOGGER.debug "Plotting ranks: "+cmd.to_s
      
      res = ""
      IO.popen(cmd) do |f|
          while line = f.gets do
            res += line 
          end
      end
      raise "rank plot failed" unless $?==0
      
      if out_file
        f = File.new(out_file, "w")
        f.puts res
      end
        
      out_file ? out_file : res
    end
    
    def self.demo_ranking_plot
      puts plot_ranking( nil, ["naive bayes", "svm", "decision tree"], [1.9, 3, 1.5], 0.1, 50) #, "/home/martin/tmp/test.svg")
    end
    
    private
    def self.transform_roc_predictions(validation_set, class_value, add_label=true )
      if (validation_set.size > 1)
        values = { :true_positives  => [], :confidence_values => []}
        (0..validation_set.size-1).each do |i|
          roc_values = validation_set.get(i).get_predictions.get_roc_prediction_values(class_value)
          values[:true_positives ] += roc_values[:true_positives ]
          values[:confidence_values] += roc_values[:confidence_values]
        end
      else
        values = validation_set.validations[0].get_predictions.get_roc_prediction_values(class_value)
      end
      tp_fp_rates = get_tp_fp_rates(values)
      labels = []
      tp_fp_rates[:youden].each do |point,confidence|
        labels << ["confidence: "+confidence.to_nice_s, point[0], point[1]]
      end if add_label
      RubyPlot::LinePlotData.new(:name => "", :x_values => tp_fp_rates[:fp_rate], :y_values => tp_fp_rates[:tp_rate], :labels => labels)
    end
    
    
    def self.transform_confidence_predictions(validation_set, class_value, add_single_folds=false)
      
      if (validation_set.size > 1)
        
        names = []; performance = []; confidence = []; faint = []
        sum_confidence_values = { :predicted_values => [], :actual_values => [], :confidence_values => []}
        
        (0..validation_set.size-1).each do |i|
          confidence_values = validation_set.get(i).get_predictions.get_prediction_values(class_value)
          sum_confidence_values[:predicted_values] += confidence_values[:predicted_values]
          sum_confidence_values[:confidence_values] += confidence_values[:confidence_values]
          sum_confidence_values[:actual_values] += confidence_values[:actual_values]
          
          if add_single_folds
            begin
              pref_conf_rates = get_performance_confidence_rates(confidence_values)
              names << "fold "+i.to_s
              performance << pref_conf_rates[:performance]
              confidence << pref_conf_rates[:confidence]
              faint << true
            rescue
              LOGGER.warn "could not get confidence vals for fold "+i.to_s
            end
          end
        end
        pref_conf_rates = get_performance_confidence_rates(sum_confidence_values, validation_set.unique_feature_type)
        names << nil # "all"
        performance << pref_conf_rates[:performance]
        confidence << pref_conf_rates[:confidence]
        faint << false
        return { :names => names, :performance => performance, :confidence => confidence, :faint => faint }
        
      else
        confidence_values = validation_set.validations[0].get_predictions.get_prediction_values(class_value)
        pref_conf_rates = get_performance_confidence_rates(confidence_values, validation_set.unique_feature_type)
        return { :names => [""], :performance => [pref_conf_rates[:performance]], :confidence => [pref_conf_rates[:confidence]] }
      end
    end    
    
    def self.demo_roc_plot
#      roc_values = {:confidence_values => [0.1, 0.9, 0.5, 0.6, 0.6, 0.6], 
#                    :predicted_values =>  [1, 0, 0, 1, 0, 1],
#                    :actual_values =>     [0, 1, 0, 0, 1, 1]}
      roc_values = {:confidence_values => [0.9, 0.8, 0.7, 0.6, 0.5, 0.4], 
                    :true_positives =>    [1, 1, 1, 0, 1, 0]}
      tp_fp_rates = get_tp_fp_rates(roc_values)
      labels = []
      tp_fp_rates[:youden].each do |point,confidence|
        labels << ["confidence: "+confidence.to_s, point[0], point[1]]
      end

      plot_data = []
      plot_data << RubyPlot::LinePlotData.new(:name => "testname", :x_values => tp_fp_rates[:fp_rate], :y_values => tp_fp_rates[:tp_rate], :labels => labels)
      RubyPlot::plot_lines("/tmp/plot.png",
        "ROC-Plot", 
        "False positive rate", 
        "True Positive Rate", plot_data )
    end
    
    def self.get_performance_confidence_rates(roc_values, feature_type)
      
      c = roc_values[:confidence_values]
      p = roc_values[:predicted_values]
      a = roc_values[:actual_values]
      raise "no prediction values for confidence plot" if p.size==0
     
      (0..p.size-2).each do |i|
        ((i+1)..p.size-1).each do |j|
          if c[i]<c[j]
            c.swap!(i,j)
            a.swap!(i,j)
            p.swap!(i,j)
          end
        end
      end
      #puts c.inspect+"\n"+a.inspect+"\n"+p.inspect+"\n\n"
      
      perf = []
      conf = []
      
      case feature_type
      when "classification"
        count = 0
        correct = 0
        (0..p.size-1).each do |i|
          count += 1
          correct += 1 if p[i]==a[i]
          if i>0 && (c[i]>=conf[-1]-0.00001)
            perf.pop
            conf.pop
          end
          perf << correct/count.to_f * 100
          conf << c[i]
        end
      when "regression"
        count = 0
        sum_squared_error = 0
        (0..p.size-1).each do |i|
          count += 1
          sum_squared_error += (p[i]-a[i])**2
          if i>0 && (c[i]>=conf[-1]-0.00001)
            perf.pop
            conf.pop
          end
          perf << Math.sqrt(sum_squared_error/count.to_f)
          conf << c[i]
        end
      end
      #puts perf.inspect
      
      return {:performance => perf,:confidence => conf}
    end
    
    
    def self.get_tp_fp_rates(roc_values)
      
      c = roc_values[:confidence_values]
      tp = roc_values[:true_positives]
      raise "no prediction values for roc-plot" if tp.size==0
      
      # hack for painting perfect/worst roc curve, otherwhise fp/tp-rate will always be 100%
      # determine if perfect/worst roc curve
      fp_found = false
      tp_found = false
      (0..tp.size-1).each do |i|
        if tp[i]==0
          fp_found |= true
        else
          tp_found |=true
        end
        break if tp_found and fp_found
      end
      unless fp_found and tp_found #if perfect/worst add wrong/right instance with lowest confidence
        tp << (tp_found ? 0 : 1)
        c << -Float::MAX
      end
      
      (0..tp.size-2).each do |i|
        ((i+1)..tp.size-1).each do |j|
          if c[i]<c[j]
            c.swap!(i,j)
            tp.swap!(i,j)
          end
        end
      end
      #puts c.inspect+"\n"+tp.inspect+"\n\n"
      
      tp_rate = [0]
      fp_rate = [0]
      w = [1]
      c2 = [Float::MAX]
      (0..tp.size-1).each do |i|
        if tp[i]==1
          tp_rate << tp_rate[-1]+1
          fp_rate << fp_rate[-1]
        else
          fp_rate << fp_rate[-1]+1
          tp_rate << tp_rate[-1]
        end
        w << 1
        c2 << c[i]
      end
      #puts c2.inspect+"\n"+tp_rate.inspect+"\n"+fp_rate.inspect+"\n"+w.inspect+"\n\n"
      
      tp_rate = tp_rate.compress_max(c2)
      fp_rate = fp_rate.compress_max(c2)
      w = w.compress_sum(c2)
      #puts tp_rate.inspect+"\n"+fp_rate.inspect+"\n"+w.inspect+"\n\n"
      
      youden = []
      (0..tp_rate.size-1).each do |i|
        tpr = tp_rate[i]/tp_rate[-1].to_f
        fpr = fp_rate[i]/fp_rate[-1].to_f
        youden << tpr + (1 - fpr)
        #puts youden[-1].to_s+" ("+tpr.to_s+" "+fpr.to_s+")"
      end
      max = youden.max
      youden_hash = {}
      (0..tp_rate.size-1).each do |i|
        if youden[i]==max and i>0
          youden_hash[i] = c2[i]
        end
      end
      #puts youden.inspect+"\n"+youden_hash.inspect+"\n\n"
      
      (0..tp_rate.size-1).each do |i|
        tp_rate[i] = tp_rate[-1]>0 ? tp_rate[i]/tp_rate[-1].to_f*100 : 100
        fp_rate[i] = fp_rate[-1]>0 ? fp_rate[i]/fp_rate[-1].to_f*100 : 100
      end
      #puts tp_rate.inspect+"\n"+fp_rate.inspect+"\n\n"
      
      youden_coordinates_hash = {}
      youden_hash.each do |i,c|
        youden_coordinates_hash[[fp_rate[i],tp_rate[i]]] = c
      end
      #puts youden_coordinates_hash.inspect+"\n\n"
      
      return {:tp_rate => tp_rate,:fp_rate => fp_rate,:youden => youden_coordinates_hash}
    end
  end
end

#require "rubygems"
#require "ruby-plot"
##Reports::PlotFactory::demo_ranking_plot
#Reports::PlotFactory::demo_roc_plot

#a = [1,    0,  1,  2,  3,  0, 2]
#puts a.compress_sum([100, 90, 70, 70, 30, 10, 0]).inspect
#puts a.compress_max([100, 90, 70, 70, 30, 10, 0]).inspect


