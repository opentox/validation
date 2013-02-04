ENV['JAVA_HOME'] = "/usr/bin" unless ENV['JAVA_HOME']
ENV['PATH'] = ENV['JAVA_HOME']+":"+ENV['PATH'] unless ENV['PATH'].split(":").index(ENV['JAVA_HOME'])
ENV['RANK_PLOTTER_JAR'] = "RankPlotter/RankPlotter.jar" unless ENV['RANK_PLOTTER_JAR']

CONF_PLOT_RANGE = { :accuracy => [0.45,1.05], :true_positive_rate => [0.45,1.05],:true_negative_rate => [0.45,1.05],
  :false_positive_rate => [0.45,1.05], :false_negative_rate => [0.45,1.05], :positive_predictive_value => [0.45,1.05],
  :negative_predictive_value => [0.45,1.05], :r_square => [0, 1.05],  :sample_correlation_coefficient => [0, 1.05],
  :concordance_correlation_coefficient => [0, 1.05] }

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
      $logger.debug "Creating regression plot, out-file:"+out_files.to_s
      
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

        if x_i.size>0
          names << ( name_attribute==:crossvalidation_fold ? "fold " : "" ) + v.send(name_attribute).to_s
          x << x_i
          y << y_i
        end
      end
      names = [""] if names.size==1 

      omit_str = omit_count>0 ? " ("+omit_count.to_s+" predictions omitted)" : ""
      raise "no predictions performed"+omit_str if x.size==0 || x[0].size==0
      out_files.each do |out_file|
        RubyPlot::regression_point_plot(out_file, "Regression plot", "Predicted values", "Actual values", names, x, y, logscale)
      end
      omit_count
    end
    
    def self.create_train_test_plot( out_files, validation_set, only_prediction_feature, waiting_task )
      if only_prediction_feature
        train = []
        test = []
        validation_set.validations.each do |v|
        [[v.test_dataset_uri, test],
         [v.training_dataset_uri, train]].each do |uri,array|
            d = Lib::DatasetCache.find(uri, validation_set.validations[0].subjectid)
            d.compounds.each do |c|
              d.data_entries[c][v.prediction_feature].each do |val|
                array << val 
              end if d.data_entries[c] and d.data_entries[c][v.prediction_feature]
            end
          end
        end
        waiting_task.progress(50) if waiting_task
        
        numerical = validation_set.unique_feature_type=="regression"
        Reports::r_util.double_hist_plot(out_files, train, test, numerical, numerical, "Training Data", "Test Data",
          "Prediction Feature Distribution", validation_set.validations.first.prediction_feature )
      else
        Reports::r_util.feature_value_plot(out_files, validation_set.validations[0].training_feature_dataset_uri,
          validation_set.validations[0].test_feature_dataset_uri, "Training Data", "Test Data",
          nil, validation_set.validations[0].subjectid, waiting_task )
      end
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
      $logger.debug "creating roc plot for '"+validation_set.size.to_s+"' validations, out-files:"+out_files.inspect
      
      data = []
      if split_set_attribute
        attribute_values = validation_set.get_values(split_set_attribute)
        attribute_values.each do |value|
          begin
            data << transform_roc_predictions(validation_set.filter({split_set_attribute => value}), class_value, false )
            data[-1].name = split_set_attribute.to_s.nice_attr+" "+value.to_s
          rescue
            $logger.warn "could not create ROC plot for "+value.to_s
          end
        end
      else
        data << transform_roc_predictions(validation_set, class_value )
      end  
      
      out_files.each do |out_file|
        RubyPlot::plot_lines(out_file, "ROC-Plot", x_label, y_label, data )
      end
    end
    
    def self.confidence_plot_class_performance( validation_set, performance_attribute, performance_accept_value )
      true_class = nil
      if performance_accept_value==nil
        perf = performance_attribute.to_s.nice_attr
      else
        invert_true_class = (validation_set.get_accept_values.size==2 and 
          validation_set.get_true_accept_value==(validation_set.get_accept_values-[performance_accept_value])[0])
        if invert_true_class && performance_attribute==:true_positive_rate 
          perf = :true_negative_rate.to_s.nice_attr
          true_class = validation_set.get_true_accept_value
        elsif invert_true_class && performance_attribute==:positive_predictive_value
          perf = :negative_predictive_value.to_s.nice_attr
          true_class = validation_set.get_true_accept_value
        else
          perf = performance_attribute.to_s.nice_attr
          true_class = performance_accept_value
        end
      end
      title = perf+" vs Confidence Plot"
      title += " (with True-Class: '"+true_class.to_s+"')" if true_class!=nil 
      {:title =>title, :performance => perf}
    end
    
    def self.create_confidence_plot( out_files, validation_set, performance_attribute, performance_accept_value, split_set_attribute=nil, show_single_curves=false )
                            
      out_files = [out_files] unless out_files.is_a?(Array)
      $logger.debug "creating confidence plot for '"+validation_set.size.to_s+"' validations, out-file:"+out_files.inspect
      
      if split_set_attribute
        attribute_values = validation_set.get_values(split_set_attribute)
        names = []
        confidence = []
        performance = []
        attribute_values.each do |value|
          begin
            data = transform_confidence_predictions(validation_set.filter({split_set_attribute => value}), performance_attribute, performance_accept_value, false)
            names << split_set_attribute.to_s.nice_attr+" "+value.to_s
            confidence << data[:confidence][0]
            performance << data[:performance][0]
          rescue
            $logger.warn "could not create confidence plot for "+value.to_s
          end
        end
        out_files.each do |out_file|
          info = confidence_plot_class_performance( validation_set, performance_attribute, performance_accept_value )
          RubyPlot::confidence_plot(out_file, info[:title], "Confidence", info[:performance], 
            names, confidence, performance, CONF_PLOT_RANGE[performance_attribute])
        end
      else
        data = transform_confidence_predictions(validation_set, performance_attribute, performance_accept_value, show_single_curves)
        out_files.each do |out_file|  
          info = confidence_plot_class_performance( validation_set, performance_attribute, performance_accept_value )
          RubyPlot::confidence_plot(out_file, info[:title], "Confidence", info[:performance], 
            data[:names], data[:confidence], data[:performance], CONF_PLOT_RANGE[performance_attribute])
        end
      end  
    end
    
    def self.create_box_plot( out_files, validation_set, title_attribute, value_attribute, class_value )
      
      out_files = [out_files] unless out_files.is_a?(Array)
      $logger.debug "creating box plot, out-files:"+out_files.inspect
      
      data = {}
      validation_set.validations.each do |v|
        value = v.send(value_attribute)
        if value.is_a?(Hash)
          if class_value==nil
            avg_value = 0
            value.values.each{ |val| avg_value+=val }
            value = avg_value/value.values.size.to_f
          else
            raise "box plot value is hash, but no entry for class-value ("+class_value.to_s+
              "); value for "+value_attribute.to_s+" -> "+value.inspect unless value.key?(class_value)
            value = value[class_value]
          end
        end
        
        data[v.send(title_attribute).to_s] = [] unless data[v.send(title_attribute).to_s]
        data[v.send(title_attribute).to_s] << value
      end
      
      Reports::r_util.boxplot( out_files, data)
    end
    
    def self.create_bar_plot( out_files, validation_set, title_attribute, value_attributes )
  
      out_files = [out_files] unless out_files.is_a?(Array)
      $logger.debug "creating bar plot, out-files:"+out_files.inspect
      
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
      
      $logger.debug "bar plot labels: "+labels.inspect 
      $logger.debug "bar plot data: "+data.inspect
      
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
      $logger.debug "Plotting ranks: "+cmd.to_s
      
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
    
    
    
    def self.transform_confidence_predictions(validation_set, performance_attribute, performance_accept_value, add_single_folds)
      
      feature_type = validation_set.unique_feature_type
      accept_values = validation_set.unique_feature_type=="classification" ? validation_set.get_accept_values : nil
      
      if (validation_set.size > 1)
        names = []; performance = []; confidence = []; faint = []
        sum_confidence_values = { :predicted_values => [], :actual_values => [], :confidence_values => []}
        
        (0..validation_set.size-1).each do |i|
          confidence_values = validation_set.get(i).get_predictions.get_prediction_values(performance_attribute, performance_accept_value)
          sum_confidence_values[:predicted_values] += confidence_values[:predicted_values]
          sum_confidence_values[:confidence_values] += confidence_values[:confidence_values]
          sum_confidence_values[:actual_values] += confidence_values[:actual_values]
          
          if add_single_folds
            begin
              perf_conf_rates = get_performance_confidence_rates(confidence_values, performance_attribute, performance_accept_value, 
                feature_type, accept_values)
              names << "fold "+i.to_s
              performance << perf_conf_rates[:performance]
              confidence << perf_conf_rates[:confidence]
              faint << true
            rescue
              $logger.warn "could not get confidence vals for fold "+i.to_s
            end
          end
        end
        perf_conf_rates = get_performance_confidence_rates(sum_confidence_values, performance_attribute, performance_accept_value, 
          feature_type, accept_values)
        names << nil # "all"
        performance << perf_conf_rates[:performance]
        confidence << perf_conf_rates[:confidence]
        faint << false
        return { :names => names, :performance => performance, :confidence => confidence, :faint => faint }
        
      else
        confidence_values = validation_set.validations[0].get_predictions.get_prediction_values(performance_attribute, performance_accept_value)
        perf_conf_rates = get_performance_confidence_rates(confidence_values, performance_attribute, performance_accept_value, 
          feature_type, accept_values)
        return { :names => [""], :performance => [perf_conf_rates[:performance]], :confidence => [perf_conf_rates[:confidence]] }
      end
    end    
    
    def self.demo_roc_plot
      
      seed = 831 #rand(1000)
      puts seed
      srand seed
      
      plot_data = []
      n = 250
      a_cutoff = 0.5
      
      a_real = []
      a_class = []
      n.times do |i|
        a_real << rand
        a_class << ( a_real[-1]>a_cutoff ? "a" : "b")
      end
      
      puts a_real.to_csv
      puts a_class.to_csv
      
      p_props = [[],[]]
      p_classes = []
      
      2.times do |index|
        
        if (index==0)
          p_noise = 0.15
          p_cutoff = 0.8
        else
          p_noise = 0.5
          p_cutoff = 0.5
        end
        
        p_real = []
        p_class = []
        p_prop = []
        correct = []
        n.times do |i|
          if rand<0.04
            p_real << rand
          else
            p_real << (a_real[i] + ((rand * p_noise) * (rand<0.5 ? 1 : -1)))
          end
          p_prop << ((p_cutoff-p_real[i]).abs)
          p_class << ( p_real[-1]>p_cutoff ? "a" : "b")
          correct << ((p_class[i]==a_class[i]) ? 1 : 0)
        end
        
        puts ""
        puts p_real.to_csv
        puts p_class.to_csv
        puts p_prop.to_csv
        
        p_prop_max = p_prop.max
        p_prop_min = p_prop.min
        p_prop_delta = p_prop_max - p_prop_min
        n.times do |i|
          p_prop[i] = (p_prop[i] - p_prop_min)/p_prop_delta.to_f
          p_props[index][i] = p_prop[i]
        end
        
        puts p_prop.to_csv
        
        p_classes << p_class
        
        (0..n-2).each do |i|
          (i+1..n-1).each do |j|
            if p_prop[i]<p_prop[j]
              tmp = p_prop[i]
              p_prop[i] = p_prop[j]
              p_prop[j] = tmp
              tmp = correct[i]
              correct[i] = correct[j]
              correct[j] = tmp
            end
          end
        end
        
        puts p_prop.to_csv
        puts correct.to_csv
        puts "acc: "+(correct.sum/n.to_f).to_s
        
        roc_values = {:confidence_values => p_prop, 
                      :true_positives =>    correct}
        tp_fp_rates = get_tp_fp_rates(roc_values)
        labels = []
        tp_fp_rates[:youden].each do |point,confidence|
          labels << ["confidence: "+confidence.to_s, point[0], point[1]]
        end
      
        plot_data << RubyPlot::LinePlotData.new(:name => "alg"+index.to_s, 
          :x_values => tp_fp_rates[:fp_rate],
          :y_values => tp_fp_rates[:tp_rate])
          #,:labels => labels)
      end
      
      puts "instance,class,prediction_1,propability_1,prediction_2,propability_2"
      n.times do |i|
        puts (i+1).to_s+","+a_class[i].to_s+","+p_classes[0][i].to_s+
          ","+p_props[0][i].to_s+
          ","+p_classes[1][i].to_s+","+p_props[1][i].to_s
      end
      RubyPlot::plot_lines("/tmp/plot.png",
        "ROC-Plot", 
        "False positive rate", 
        "True Positive Rate", plot_data )
    end
    
    def self.get_performance_confidence_rates(pred_values, performance_attribute, performance_accept_value, feature_type, accept_values)
      
      c = pred_values[:confidence_values]
      p = pred_values[:predicted_values]
      a = pred_values[:actual_values]
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
      predictions = nil       
      (0..p.size-1).each do |i|
        # melt nearly identical confidence values to get a smoother graph
        if i>0 && (c[i]>=conf[-1]-0.00001)
          perf.pop
          conf.pop
        end
        if (predictions == nil)
          data = {:predicted_values => [p[i]],:actual_values => [a[i]], :confidence_values => [c[i]], 
            :feature_type => feature_type, :accept_values => accept_values}
          predictions = Lib::Predictions.new(data)
        else
          predictions.update_stats(p[i], a[i], c[i])
        end
        
        val = predictions.send(performance_attribute)
        val = val[performance_accept_value] if val.is_a?(Hash)
        perf << val
        conf << c[i]
      end
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

#require "./rubygems"
#require "./ruby-plot"
###Reports::PlotFactory::demo_ranking_plot
#class Array
#  def sum
#    inject( nil ) { |sum,x| sum ? sum+x : x }
#  end
#  
#  def to_csv
#    s = ""
#    each do |x|
#      s += (x.is_a?(Float) ? ("%.3f"%x) : ("    "+x.to_s) )+", "
#    end
#    s
#  end
#end
#Reports::PlotFactory::demo_roc_plot

#a = [1,    0,  1,  2,  3,  0, 2]
#puts a.compress_sum([100, 90, 70, 70, 30, 10, 0]).inspect
#puts a.compress_max([100, 90, 70, 70, 30, 10, 0]).inspect


