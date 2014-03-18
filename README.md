OpenTox Validation
==================

* An OpenTox REST Webservice for validation and reporting

[API documentation](http://rdoc.info/github/opentox/validation)
--------------------------------------------------------------

General:
--------

* validation and reporting is seperated in code (see below)
* see validation/README and report/README for more general info

Source Directories:
-------------------

* **validation** all validation stuff excluding the reports (should not access code in *report*)
* **report** reporting stuff (should not access code in *validation*)
* **lib** helper classes used by validation and by report 
* **test** test examples and use-cases (additional to those in the test repository)

Non-Source Directories:
-----------------------

* **data** data files for validation
* **docbook-xml-4.5** for converting xml reports into html
* **docbook-xsl-1.76.1** for converting xml repors into html
* **RankPlotter** for creating rank-plots in compare-algorithm reports
* **reports** reports are stored in this folder
* **resources** icons and stylsheet

Glossary / Wording:
-------------------

* **accept_values** domain or possible class-values for classification (e.g. 'active','inactive')
* **prediction_feature** endpoint feature that is predicted (exists once in cross-valdation)
* **predicted_variable** feature for predictions of a model (exists 10 times in 10-fold cross-valdation)
* **predicted_confidence** feature for predicted-confidence of a model (exists 10 times in 10-fold cross-validation)

Copyright (c) 2009-2012 Martin Guetlein, Christoph Helma. See LICENSE for details.
