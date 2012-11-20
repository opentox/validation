
require 'test/test_examples_util.rb'

class Class
  def humanize
    self.to_s.gsub(/.*::/, "").gsub(/([^^A-Z_])([A-Z])/, '\1-\2').gsub(/_/,"-")
  end
end

module ValidationExamples
  
  class IrisCrossvalidation < CrossValidation
    def initialize
      @dataset_file = File.new("data/IRIS_unitrisk.yaml","r")
      @prediction_feature = "http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk"
      @num_folds = 10
    end
  end
  
  class MajorityIrisCrossvalidation < IrisCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/regr/algorithm")
      super
    end
  end

  class LazarIrisCrossvalidation < IrisCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer")
      super
    end
  end
  
  ########################################################################################################  
  
  class IrisSplit < SplitTestValidation
    def initialize
      @dataset_file = File.new("data/IRIS_unitrisk.yaml","r")
      @prediction_feature = "http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk"
    end
  end
  
  class LazarIrisSplit < IrisSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer")
      super
    end
  end
  
  class MajorityIrisSplit < IrisSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/regr/algorithm")
      super
    end
  end
  
  ########################################################################################################  
  
  class EPAFHMSplit < SplitTestValidation
    def initialize
      @dataset_file = File.new("data/EPAFHM.csv","r")
      #@prediction_feature = "http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk"
      @split_ratio = 0.95
    end
  end
    
  class LazarEPAFHMSplit < EPAFHMSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  class LazarLastEPAFHMSplit < LazarEPAFHMSplit
    def initialize
      super
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/last")
    end
  end

  
  class MajorityEPAFHMSplit < EPAFHMSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/regr/algorithm")
      super
    end
  end
  
    class MajorityRandomEPAFHMSplit < MajorityEPAFHMSplit
    def initialize
      @algorithm_params = "random=true"
      super
    end
  end
  
    ########################################################################################################
  
    class EPAFHMCrossvalidation < CrossValidation
    def initialize
      @dataset_file = File.new("data/EPAFHM.csv","r")
      #@prediction_feature = "http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk"
      @num_folds = 10
    end
  end
  
  class MajorityEPAFHMCrossvalidation < EPAFHMCrossvalidation
    def initialize
      #@dataset_uri = "http://local-ot/dataset/2366"
      #@prediction_feature = "http://local-ot/dataset/2366/feature/LC50_mmol"
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/regr/algorithm")
      super
    end
  end

  class MajorityRandomEPAFHMCrossvalidation < MajorityEPAFHMCrossvalidation
    def initialize
      @algorithm_params = "random=true"
      super
    end
  end

  class LazarEPAFHMCrossvalidation < EPAFHMCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  ########################################################################################################
  
  class HamsterSplit < SplitTestValidation
    def initialize
      #@dataset_file = File.new("data/hamster_carcinogenicity.yaml","r")
      @dataset_file = File.new("data/hamster_carcinogenicity.csv","r")
      
      #@prediction_feature = "http://local-ot/toxmodel/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
      #@prediction_feature = "http://local-ot/dataset/1/feature/hamster_carcinogenicity"
    end
  end
  
  class LazarHamsterSplit < HamsterSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end

  class LazarLastHamsterSplit < LazarHamsterSplit
    def initialize
      super
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/last")
    end
  end

  
  class MajorityHamsterSplit < HamsterSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end
  
    class MajorityRandomHamsterSplit < MajorityHamsterSplit
    def initialize
      @algorithm_params = "random=true"
      super
    end
  end
  
  ########################################################################################################
  
  class HamsterBootstrapping < BootstrappingValidation
    def initialize
      #@dataset_file = File.new("data/hamster_carcinogenicity.yaml","r")
      @dataset_file = File.new("data/hamster_carcinogenicity.csv","r")
      
      #@prediction_feature = "http://local-ot/toxmodel/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
      #@prediction_feature = "http://local-ot/dataset/1/feature/hamster_carcinogenicity"
    end
  end
  
  class LazarHamsterBootstrapping < HamsterBootstrapping
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  class MajorityHamsterBootstrapping < HamsterBootstrapping
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end  
  
  ########################################################################################################

  class HamsterTrainingTest < TrainingTestValidation
    def initialize
#      @training_dataset_file = File.new("data/hamster_carcinogenicity.train.yaml","r")
#      @test_dataset_file = File.new("data/hamster_carcinogenicity.test.yaml","r")
      
      @training_dataset_file = File.new("data/hamster_carcinogenicity.train.csv","r")
      @test_dataset_file = File.new("data/hamster_carcinogenicity.test.csv","r")
      
      
      #@prediction_feature = "http://local-ot/toxmodel/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
      #@prediction_feature = "http://local-ot/dataset/1/feature/hamster_carcinogenicity"
    end
  end
  
  class MajorityHamsterTrainingTest < HamsterTrainingTest
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end
  
  class LazarHamsterTrainingTest < HamsterTrainingTest
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  ########################################################################################################  

  class HamsterCrossvalidation < CrossValidation
    def initialize
      #@dataset_file = File.new("data/hamster_carcinogenicity.yaml","r")
      @dataset_file = File.new("data/hamster_carcinogenicity.csv","r")
      
      #@prediction_feature = "http://local-ot/toxmodel/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
      #@prediction_feature = "http://local-ot/dataset/1/feature/hamster_carcinogenicity"
      @num_folds = 10
    end
  end
  
  class MajorityHamsterCrossvalidation < HamsterCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end
  
    class MajorityRandomHamsterCrossvalidation < MajorityHamsterCrossvalidation
    def initialize
      @algorithm_params = "random=true"
      super
    end
  end

  class LazarHamsterCrossvalidation < HamsterCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  class LazarLastHamsterCrossvalidation < LazarHamsterCrossvalidation
    def initialize
      super
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/last")
    end
  end
  
  ########################################################################################################  

  class HamsterLooCrossvalidation < LooCrossValidation
    def initialize
      @dataset_file = File.new("data/hamster_carcinogenicity.csv","r")
    end
  end
  
  class LazarHamsterLooCrossvalidation < HamsterLooCrossvalidation
      def initialize
        @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
        @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
        super
      end
    end
    
  ########################################################################################################
  
  class LazarHamsterMiniCrossvalidation < CrossValidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      @dataset_file = File.new("data/hamster_carcinogenicity.mini.csv","r")
      @num_folds = 2
    end
  end  
  
  class ISSCANStratifiedCrossvalidation < CrossValidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      @dataset_file = File.new("data/ISSCAN_v3a_canc-red.csv","r")
      @stratified = true
      @num_folds = 10
    end
  end  
  
  class ISSCAN2StratifiedCrossvalidation < CrossValidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      @dataset_file = File.new("data/ISSCAN_v3a_sal.csv","r")
      @stratified = true
      @num_folds = 10
    end
  end  
  
  
  ########################################################################################################  

  class ISTHamsterCrossvalidation < CrossValidation
    def initialize
      @dataset_uri = "http://webservices.in-silico.ch/dataset/108"
      @prediction_feature = "http://toxcreate.org/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
    end
  end
  
  class MajorityISTHamsterCrossvalidation < ISTHamsterCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end
  
  class LazarISTHamsterCrossvalidation < ISTHamsterCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer")
      super
    end
  end
  
  class ISTLazarISTHamsterCrossvalidation < ISTHamsterCrossvalidation
    def initialize
      @algorithm_uri = "http://webservices.in-silico.ch/algorithm/lazar"
      @algorithm_params = "feature_generation_uri=http://webservices.in-silico.ch/algorithm/fminer"
      super
    end
  end
  
  ########################################################################################################  

  class ISTIrisCrossvalidation < CrossValidation
    def initialize
      @dataset_uri = "http://ot-dev.in-silico.ch/dataset/39"
      @prediction_feature = "http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk"
    end
  end
  
  class ISTLazarISTIrisCrossvalidation < ISTIrisCrossvalidation
    def initialize
      @algorithm_uri = "http://ot-dev.in-silico.ch/algorithm/lazar"
      @algorithm_params = "feature_generation_uri=http://ot-dev.in-silico.ch/algorithm/fminer"
      super
    end
  end
  
    ########################################################################################################  

  class ISTRatLiverCrossvalidation < CrossValidation
    def initialize
      @dataset_uri = "http://webservices.in-silico.ch/dataset/26"
      @prediction_feature = "http://toxcreate.org/feature#chr_rat_liver_proliferativelesions"
    end
  end
  
  class MajorityISTRatLiverCrossvalidation < ISTRatLiverCrossvalidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end

      ########################################################################################################  

  class ISTEpaCrossvalidation < CrossValidation
    def initialize
      @dataset_uri = "http://ot-dev.in-silico.ch/dataset/69"
      @prediction_feature = "http://ot-dev.in-silico.ch/toxcreate/feature#EPA%20FHM"
    end
  end
  
  class ISTLazarISTEpaCrossvalidation < ISTEpaCrossvalidation
    def initialize
      @algorithm_uri = "http://ot-dev.in-silico.ch/algorithm/lazar"
      @algorithm_params = "feature_generation_uri=http://ot-dev.in-silico.ch/algorithm/fminer"
      super
    end
  end
  
  ########################################################################################################

  
  ########################################################################################################
  
  class LR_AmbitCacoModel < ModelValidation
    def initialize
#      @model_uri = "http://apps.ideaconsult.net:8080/ambit2/model/33"
#      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      #@prediction_feature=http://apps.ideaconsult.net:8080/ambit2/feature/22200
      
      @model_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/model/33"
      @test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R545"
      
    end
  end
  
  ########################################################################################################

  class CacoTrainingTest < TrainingTestValidation
    def initialize
      @training_dataset_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/R7798"
      @test_dataset_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/R8353"
      @prediction_feature = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/255510"
    end
  end
  
  class LR_AmbitCacoTrainingTest < CacoTrainingTest
    def initialize
      @algorithm_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/algorithm/LR"
      super
    end
  end
  
  class MLR_NTUA_CacoTrainingTest < CacoTrainingTest
    def initialize
      @algorithm_uri = "http://opentox.ntua.gr:3003/algorithm/mlr"
      super
    end
  end
  
  class MLR_NTUA2_CacoTrainingTest < CacoTrainingTest
    def initialize
      @algorithm_uri = "http://opentox.ntua.gr:3004/algorithm/mlr"
      super
    end
  end
  
  class MajorityCacoTrainingTest < CacoTrainingTest
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/regr/algorithm")
      super
    end
  end
  
  ########################################################################################################
  
  class NtuaModel < ModelValidation
    def initialize
      @model_uri = "http://opentox.ntua.gr:4000/model/0d8a9a27-3481-4450-bca1-d420a791de9d"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/54"
      #@prediction_feature=http://apps.ideaconsult.net:8080/ambit2/feature/22200
    end
  end
  
  class NtuaModel2 < ModelValidation
    def initialize
      @model_uri = "http://opentox.ntua.gr:8080/model/11093fbc-3b8b-41e2-bfe3-d83f5f529efc"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/54"
      @prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/579820"
    end
  end
  
  class NtuaModel3 < ModelValidation
    def initialize
      @model_uri = "http://opentox.ntua.gr:8080/model/bbab3714-e90b-4990-bef9-8e7d3a30eece"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      #@prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/579820"
    end
  end  
  
  ########################################################################################################
  
  class NtuaTrainingTest < TrainingTestValidation
    def initialize
      @algorithm_uri = "http://opentox.ntua.gr:8080/algorithm/mlr"
      @training_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/22200"
    end
  end  

  class NtuaTrainingTestSplit < SplitTestValidation
    def initialize
      @algorithm_uri = "http://opentox.ntua.gr:8080/algorithm/mlr"
      @dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/22200"
    end
  end  
  
    class NtuaCrossvalidation < CrossValidation
    def initialize
      @algorithm_uri = "http://opentox.ntua.gr:8080/algorithm/mlr"
      @dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/22200"
    end
  end  
  
  class AmbitVsNtuaTrainingTest < TrainingTestValidation
    def initialize
      @algorithm_uri = "http://apps.ideaconsult.net:8080/ambit2/algorithm/LR"
      @training_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/22200"
    end
  end  
  
  class AnotherAmbitJ48TrainingTest < TrainingTestValidation
    def initialize
      @algorithm_uri = "http://apps.ideaconsult.net:8080/ambit2/algorithm/J48"
      @training_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/585758"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/585758"
      @prediction_feature= "http://apps.ideaconsult.net:8080/ambit2/feature/111148"
    end
  end    

 class TumTrainingTest < TrainingTestValidation
    def initialize
      @algorithm_uri = "http://lxkramer34.informatik.tu-muenchen.de:8080/OpenTox-dev/algorithm/kNNclassification"
      @training_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/585758"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/585758"
      @prediction_feature= "http://apps.ideaconsult.net:8080/ambit2/feature/111148"
    end
  end    

  
 
  
  class LazarVsNtuaCrossvalidation < CrossValidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      @dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R545"
      @prediction_feature="http://apps.ideaconsult.net:8080/ambit2/feature/22200"
      @num_folds=3
    end
  end  


#  loading prediciton via test-dataset:'http://apps.ideaconsult.net:8080/ambit2/dataset/R545', 
#  test-target-datset:'', prediction-dataset:'http://apps.ideaconsult.net:8080/ambit2/dataset/584389', 
#  prediction_feature: 'http://apps.ideaconsult.net:8080/ambit2/feature/22200' ', predicted_variable: 'http://apps.ideaconsult.net:8080/ambit2/feature/627667'           :: /ot_predictions.rb:21:in `initialize'
#D, [2011-05-11T13:47:26.631628 #22952] DEBUG -- : validation         :: 
  ########################################################################################################
  
  class TumModel < ModelValidation
    def initialize
      @model_uri = "http://opentox-dev.informatik.tu-muenchen.de:8080/OpenTox-sec/sec/model/TUMOpenToxModel_M5P_5"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/99488"
    end
  end  
  
  ########################################################################################################
  
  class AmbitModelValidation < ModelValidation
    def initialize
      @model_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/model/39319"
      #@model_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/model/29139"
      @test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401577?max=3"
    end
  end    
  
  class AmbitBursiModelValidation < ModelValidation
    def initialize
      @model_uri =  "https://ambit.uni-plovdiv.bg:8443/ambit2/model/35194"
      @test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401577"
    end
  end
  
  class AmbitAquaticModelValidation < ModelValidation
    def initialize
      @model_uri =  "http://apps.ideaconsult.net:8080/ambit2/model/130668"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/186293?feature_uris[]=http://apps.ideaconsult.net:8080/ambit2/feature/430904&feature_uris[]=http://apps.ideaconsult.net:8080/ambit2/feature/430905"
      @prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/430905"
    end
  end  
  
  class AmbitXYModelValidation < ModelValidation
    def initialize
      @model_uri =  "http://apps.ideaconsult.net:8080/ambit2/model/237692"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R736156"
      @prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/430905"
    end
  end 
  
    class AmbitXYZModelValidation < ModelValidation
    def initialize
      @model_uri =  "http://apps.ideaconsult.net:8080/ambit2/model/238008"
      @test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/R736396"
      #@prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/430905" ??
    end
  end 
  
  
  class AmbitTrainingTest < TrainingTestValidation
    def initialize
      @training_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401560"
      #@training_dataset_uri = "http://opentox.informatik.uni-freiburg.de/dataset/317"
      @test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401560"
      @prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/22190"
      @algorithm_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/algorithm/LR"
    end
  end   
  
  class AmbitBursiTrainingTest < TrainingTestValidation
    def initialize
      @test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401577"
      @training_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401577"
      @prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/26221"
      @algorithm_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/algorithm/J48"
    end
  end    
  
  class AmbitJ48TrainingTest < TrainingTestValidation
    def initialize
      @test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/39914"
      @training_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/39914"
      @prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/221726"
      @algorithm_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/algorithm/J48"
    end
  end  
  
  class AmbitTrainingTestSplit < SplitTestValidation
    def initialize
      #@model_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/model/29139"
      @dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401560"
      #@test_dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401560"
      @prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/22190"
      @algorithm_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/algorithm/LR"
    end
  end  
  
  class AmbitBursiTrainingTestSplit < SplitTestValidation
    def initialize
      @dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401577"
      @prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/26221"
      @algorithm_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/algorithm/J48"
    end
  end    
  
  class AmbitJ48TrainingTestSplit < SplitTestValidation
    def initialize
      @dataset_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/39914"
      @prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/221726"
      @algorithm_uri = "https://ambit.uni-plovdiv.bg:8443/ambit2/algorithm/J48"
    end
  end    
  
  
   ########################################################################################################
   
  class HamsterTrainingTest < TrainingTestValidation
    def initialize
#      @training_dataset_file = File.new("data/hamster_carcinogenicity.train.yaml","r")
#      @test_dataset_file = File.new("data/hamster_carcinogenicity.test.yaml","r")
      
      @training_dataset_file = File.new("data/hamster_carcinogenicity.train.csv","r")
      @test_dataset_file = File.new("data/hamster_carcinogenicity.test.csv","r")
      
      
      #@prediction_feature = "http://local-ot/toxmodel/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
      #@prediction_feature = "http://local-ot/dataset/1/feature/hamster_carcinogenicity"
    end
  end
  
  class MajorityHamsterTrainingTest < HamsterTrainingTest
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end
  
  ########################################################################################################
  
  class RepdoseSplit < SplitTestValidation
    def initialize
      @dataset_file = File.new("data/repdose_classification.csv","r")
    end
  end
  
  class LazarRepdoseSplit < RepdoseSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  class MajorityRepdoseSplit < RepdoseSplit
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end  
  
    ########################################################################################################
  
  class RepdoseCrossValidation < CrossValidation
    def initialize
      @dataset_file = File.new("data/repdose_classification.csv","r")
    end
  end
  
  class LazarRepdoseCrossValidation < RepdoseCrossValidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"lazar")
      @algorithm_params = "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
      super
    end
  end
  
  class MajorityRepdoseCrossValidation < RepdoseCrossValidation
    def initialize
      @algorithm_uri = File.join(CONFIG[:services]["opentox-majority"],"/class/algorithm")
      super
    end
  end  
  
      ########################################################################################################
  
  class TumCrossValidation < CrossValidation
    def initialize
      @dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/124963"
      @algorithm_uri = "http://opentox:8080/OpenTox/algorithm/kNNregression"
      @prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/121905"
      @num_folds=2
      super
    end
  end
  
   ########################################################################################################
  
  @@list = {
      "1" => [ LazarHamsterSplit, MajorityHamsterSplit, MajorityRandomHamsterSplit ],
      "1a" => [ LazarHamsterSplit ],
      "1b" => [ MajorityHamsterSplit ],
      "1c" => [ MajorityRandomHamsterSplit ],
      "1d" => [ LazarLastHamsterSplit ],
      
      "2" => [ LazarHamsterTrainingTest, MajorityHamsterTrainingTest ],
      "2a" => [ LazarHamsterTrainingTest ],
      "2b" => [ MajorityHamsterTrainingTest ],
      
      "3" => [ LazarHamsterCrossvalidation, MajorityHamsterCrossvalidation, MajorityRandomHamsterCrossvalidation ],
      "3a" => [ LazarHamsterCrossvalidation ],
      "3b" => [ MajorityHamsterCrossvalidation ],
      "3c" => [ MajorityRandomHamsterCrossvalidation ],
      "3d" => [ LazarLastHamsterCrossvalidation ],
      
      "4" => [ MajorityISTHamsterCrossvalidation, LazarISTHamsterCrossvalidation, ISTLazarISTHamsterCrossvalidation ],
      "4a" => [ MajorityISTHamsterCrossvalidation ],
      "4b" => [ LazarISTHamsterCrossvalidation ],
      "4c" => [ ISTLazarISTHamsterCrossvalidation ],
      
      "5a" => [ LR_AmbitCacoModel ],
      
      "6" => [ LR_AmbitCacoTrainingTest, MLR_NTUA_CacoTrainingTest, MLR_NTUA2_CacoTrainingTest, MajorityCacoTrainingTest ],
      "6a" => [ LR_AmbitCacoTrainingTest ],
      "6b" => [ MLR_NTUA_CacoTrainingTest ],
      "6c" => [ MLR_NTUA2_CacoTrainingTest ],
      "6d" => [ MajorityCacoTrainingTest ],
      
      "7a" =>  [ LazarIrisSplit ],
      "7b" =>  [ MajorityIrisSplit ],
      
      "8a" => [ LazarIrisCrossvalidation ],
      "8b" => [ MajorityIrisCrossvalidation ],
      
      "9a" => [ ISTLazarISTIrisCrossvalidation ],
      
      "10a" => [ ISTLazarISTEpaCrossvalidation ],
      
      "11b" => [ MajorityISTRatLiverCrossvalidation ],
      
      "12" => [ LazarHamsterBootstrapping, MajorityHamsterBootstrapping ],
      "12a" => [ LazarHamsterBootstrapping ],
      "12b" => [ MajorityHamsterBootstrapping ],
      
      "13a" =>  [ LazarEPAFHMSplit ],
      "13b" =>  [ MajorityEPAFHMSplit ],
      "13c" =>  [ MajorityRandomEPAFHMSplit ],
      "13d" =>  [ LazarLastEPAFHMSplit ],
      
      "14" =>   [ LazarEPAFHMCrossvalidation, MajorityEPAFHMCrossvalidation, MajorityRandomEPAFHMCrossvalidation ],
      "14a" =>  [ LazarEPAFHMCrossvalidation ],
      "14b" =>  [ MajorityEPAFHMCrossvalidation ],
      "14c" =>  [ MajorityRandomEPAFHMCrossvalidation ],
      
      "15a" =>  [ NtuaModel ],
      "15b" =>  [ NtuaModel2 ],
      "15c" =>  [ NtuaModel3 ],
      
      "16" => [ LazarRepdoseSplit, MajorityRepdoseSplit ],
      "16a" => [ LazarRepdoseSplit ],
      "16b" => [ MajorityRepdoseSplit ],      
      
      "17" => [ LazarRepdoseCrossValidation, MajorityRepdoseCrossValidation ],
      "17a" => [ LazarRepdoseCrossValidation ],
      "17b" => [ MajorityRepdoseCrossValidation ],
      
      "18a" =>  [ TumModel ],
      
      "19a" =>  [ AmbitModelValidation ],
      "19b" =>  [ AmbitTrainingTest ],
      "19c" =>  [ AmbitTrainingTestSplit ],
      "19d" => [ AmbitBursiTrainingTest ],
      "19e" => [ AmbitBursiModelValidation ],
      "19f" => [ AmbitBursiTrainingTestSplit ],
      "19g" => [ AmbitJ48TrainingTest ],
      "19h" => [ AmbitJ48TrainingTestSplit ],
      "19i" => [ AmbitAquaticModelValidation ],
      "19j" => [ AmbitXYModelValidation ],
      
      "20a" => [ TumCrossValidation ],
      
      "21a" => [ LazarHamsterMiniCrossvalidation ],
      "21b" => [ ISSCANStratifiedCrossvalidation ],
      "21c" => [ ISSCAN2StratifiedCrossvalidation ],
      
      "22a" =>  [ NtuaTrainingTest ],
      "22b" =>  [ NtuaTrainingTestSplit ],
      "22c" =>  [ NtuaCrossvalidation ],
      "22d" =>  [ LazarVsNtuaCrossvalidation ],

      #impt      
      "22e" =>  [ AmbitVsNtuaTrainingTest ],
      "22f" =>  [ AnotherAmbitJ48TrainingTest ],
      "22g" =>  [ TumTrainingTest ],
        
      "23a" => [ LazarHamsterLooCrossvalidation ],
      
    }
  
  def self.list
    @@list.sort.collect{|k,v| k+":\t"+v.collect{|vv| vv.humanize}.join("\n\t")+"\n"}.to_s #.join("\n")
  end
  
  def self.select(csv_keys)
    res = []
    if csv_keys!=nil and csv_keys.size>0
      csv_keys.split(",").each do |k|
        raise "no key "+k.to_s unless @@list.has_key?(k)
        res << @@list[k]
      end
    end
    return res
  end
  
end

#puts ValidationExamples.list
#puts ValidationExamples.select("1,2a").inspect
