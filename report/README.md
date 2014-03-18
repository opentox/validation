Directory: report - OpenTox Validation
=======================================

author: Martin Guetlein, date: 2014-03-18

General
-------

* reports are no 'html-view' of validations
* instead reports are own objects and created for validations and seperately stored
* report types: 
 * **valdation** for a single validation
 * **crossvalidation** for a cross-validation
 * **algorithm-comparison** compares cross-validation of different-algorithms on >=1 datasets
 * **method-comparison** compares arbitrary single validations
* reports are stored as docbook-xml files with additional plotfiles
* **IMPORTANT** reports have a own representation of validations (see validation_data.rb, not objects in validation/validation_db.rb)

Code
----

* **environment.rb** requires all gems/files, inits r-util
* **report_application.rb** REST call handling
* **report_service.rb** provides/deletes reports
* **report_factory.rb** creates various report types
* **report_content.rb** fills report content, wrap xml-report + plot-files
* **xml_report.rb** xml-object, this is the actual report content
* **xml_report_util.rb** utils for xml report
* **plot_factory.rb** creates plots
* **report_format.rb** formats reports (to html/pdf)
* **report_persistance.rb** handles storing of reports (stored as file and in redis)
* **report_test.rb** debugging and testing stuff
* **statistical_test.rb** applies t-test for significant different performance 
* **util.rb** various utils 
* **validation_access.rb** how validations are accessed in reports
* **validation_data.rb** how validations are represented in reports
