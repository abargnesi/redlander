# -*- coding: utf-8 -*-
require "spec_helper"

describe Model do
  let(:model) { described_class.new }
  subject { model }

  describe "size" do
    subject { model.size }

    context "for a non-countable storage" do
      before do
        model.statements.create(statement_attributes)
        Redland.stub(:librdf_model_size => -1)
      end

      it "should return size derived from count" do
        subject.should eql model.statements.count
      end
    end
  end

  describe "query" do
    let(:project) { URI("http://rubygems.org/gems/rdf") }
    subject { model.query(q) }
    before { model.from_file(Redlander.fixture_path("doap.ttl"), :format => "turtle") }

    describe "SPARQL" do
      describe "SELECT" do
        context "for a single result" do
          let(:q) { "PREFIX doap: <http://usefulinc.com/ns/doap#> SELECT ?subject WHERE { ?subject doap:name 'RDF.rb' . ?subject doap:platform 'Ruby' }" }

          it { should be_a Enumerable }

          it "should return an array of binding hashes" do
            expect(subject.size).to eql 1
            expect(subject.first["subject"]).to be_a Redlander::Node
            expect(subject.first["subject"].value).to eql project
          end

          context "with a block" do
            it "should yield a binding hash" do
              model.query(q) do |binding|
                expect(binding).to be_a Hash
                expect(binding["subject"]).to be_a Redlander::Node
                expect(binding["subject"].value).to eql project
              end
            end
          end
        end

        context "for multiple results" do
          let(:q) { "PREFIX doap: <http://usefulinc.com/ns/doap#> PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT ?name WHERE { <http://rubygems.org/gems/rdf> doap:helper [ foaf:name ?name ] }" }

          it "should yield multiple bindings" do
            # TODO: librdf screws up the input UTF-8 encoding
            helpers = ["Călin Ardelean", "Danny Gagne", "Joey Geiger", "Fumihiro Kato", "Naoki Kawamukai", "Hellekin O. Wolf", "John Fieber", "Keita Urashima", "Pius Uzamere"]

            expect(subject.size).to eql helpers.size
            subject.each do |binding|
              expect(helpers).to include binding["name"].value
            end
          end
        end
      end

      describe "ASK" do
        let(:q) { "PREFIX doap: <http://usefulinc.com/ns/doap#> ASK { <http://rubygems.org/gems/rdf> doap:homepage <http://rdf.rubyforge.org/> }" }

        it { should be_true }
      end

      describe "CONSTRUCT" do
        let(:q) { "PREFIX doap: <http://usefulinc.com/ns/doap#> CONSTRUCT { ?project doap:framework 'RDF'^^<http://www.w3.org/2001/XMLSchema#string> } WHERE { ?project a doap:Project }" }

        it { should be_a Redlander::Model }

        it "should return a model made from the constructed statements" do
          statement = Redlander::Statement.new(:subject => URI("http://rubygems.org/gems/rdf"),
                                               :predicate => URI("http://usefulinc.com/ns/doap#framework"),
                                               :object => "RDF")
          expect(subject.statements.count).to eql 1
          expect(subject.statements.exist?(statement)).to be_true
        end
      end

      describe "DESCRIBE" do
        let(:q) { "PREFIX doap: <http://usefulinc.com/ns/doap#> DESCRIBE ?gem WHERE { ?gem a doap:Project }" }

        it { pending "Not implemented. See: http://bugs.librdf.org/mantis/view.php?id=135" }
      end
    end
  end

  describe "merge" do
    before do
      @model2 = Redlander::Model.new
      @model3 = Redlander::Model.new
      @statement1 = Redlander::Statement.new(:subject => URI("http://rubygems.org/gems/rdf"),
                                             :predicate => URI("http://usefulinc.com/ns/doap#framework"),
                                             :object => "RDF")
      model.statements.add(@statement1)
      @statement2 = Redlander::Statement.new(:subject => URI("http://rubygems.org/gems/rdfs"),
                                             :predicate => URI("http://usefulinc.com/ns/doap#framework"),
                                             :object => "RDFS")
      @model2.statements.add(@statement2)
      @model3.statements.add(@statement1)
    end

    it "should return model" do
      expect(model.merge(@model2)).to eql model
    end

    it "should add different model statements" do
      expect { model.merge(@model2) }.to change(model, :size).by(1)
      expect(model.statements).to include(@statement1)
      expect(model.statements).to include(@statement2)
    end

    it "should add same model statements" do
      expect { model.merge(@model3) }.not_to change(model, :size)
      expect(model.statements).to include(@statement1)
    end
  end

  describe "statements" do
    subject { model.statements }

    it { should be_an_instance_of(ModelProxy) }

    context "when enumerated" do
      context "without a block" do
        subject { model.statements.each }

        it { should be_a Enumerator }
      end

      context "with a block" do
        before do
          @statement = subject.create(statement_attributes)
          @statements = []
        end

        it "should be iterated over" do
          expect {
            model.statements.each { |s| @statements << s }
          }.to change(@statements, :count).by(1)
          expect(@statements).to include @statement
        end
      end
    end

    context "when searched" do
      subject { model.statements.find(:first, @conditions) }
      before { @statement = model.statements.create(statement_attributes) }

      context "with empty conditions" do
        before { @conditions = {} }

        it { should eql @statement }
      end

      context "with matching conditions" do
        before { @conditions = {:object => @statement.object} }

        it { should eql @statement }
      end

      context "with non-matching conditions" do
        before { @conditions = {:object => "another object"} }

        it { should be_nil }
      end

      context "for all matching statements" do
        subject { model.statements.find(:all, @conditions) }

        before do
          @another_statement =
            model.statements.create(statement_attributes.merge(:subject => URI.parse('http://example.com/concepts#another_subject')))
        end

        context "with empty conditions" do
          before { @conditions = {} }

          it { should eql [@statement, @another_statement] }
        end

        context "with one matching statement" do
          before { @conditions = {:subject => @statement.subject} }

          it { should eql [@statement] }
        end

        context "with all matching statements" do
          before { @conditions = {:object => @statement.object} }

          it { should eql [@statement, @another_statement] }
        end

        context "with no matching statements" do
          before { @conditions = {:object => "no match"} }

          it { should be_empty }
        end
      end
    end

    context "when checked for existance" do
      subject { model.statements.exist?(@conditions) }
      before { @statement = model.statements.create(statement_attributes) }

      context "with matching conditions" do
        before { @conditions = {:object => @statement.object} }

        it { should be_true }
      end

      context "with non-matching conditions" do
        before { @conditions = {:object => "another object"} }

        it { should be_false }
      end
    end

    context "when adding" do
      context "via #create" do
        it "should be created in the model" do
          expect { subject.create(statement_attributes) }.to change(subject, :count).by(1)
        end

        it "should not add duplicate statements" do
          expect {
            2.times { subject.create(statement_attributes) }
          }.to change(subject, :count).by(1)
        end
      end

      context "via #add" do
        before { @statement = Statement.new(statement_attributes) }

        it "should be added to the model" do
          expect { subject.add(@statement) }.to change(subject, :count).by(1)
          subject.should include(@statement)
        end

        it "should not add duplicate statements" do
          expect {
            2.times { subject.add(@statement) }
          }.to change(subject, :count).by(1)
        end
      end
    end

    context "when deleting" do
      before { @statement = subject.create(statement_attributes) }

      it "should be removed from the model" do
        expect { subject.delete(@statement) }.to change(subject, :count).by(-1)
        subject.should_not include(@statement)
      end

      describe "all statements" do
        before { subject.create(statement_attributes.merge(:object => "another one")) }

        it "should selectively delete statements" do
          expect { subject.delete_all(:object => "another one") }.to change(subject, :count).by(-1)
        end

        it "should completely wipe the model" do
          expect { subject.delete_all }.to change(subject, :count).from(2).to(0)
        end
      end
    end
  end

  describe "serialization" do
    before do
      s = URI.parse("http://example.com/concepts#two-dimensional_seismic_imaging")
      p = URI.parse("http://www.w3.org/2000/01/rdf-schema#label")
      o = "2-D seismic imaging@en"
      subject.statements.create(:subject => s, :predicate => p, :object => o)
    end

    it "should produce RDF/XML content" do
      content = subject.to_rdfxml
      content.should be_an_instance_of(String)
      content.should include('2-D seismic imaging')
    end

    it "should produce N-Triples content" do
      content = subject.to_ntriples
      content.should be_an_instance_of(String)
      content.should include('2-D seismic imaging@en')
    end

    it "should produce Turtle content" do
      content = subject.to_turtle
      content.should be_an_instance_of(String)
      content.should include('2-D seismic imaging@en')
    end

    it "should produce JSON content" do
      content = subject.to_json
      content.should be_an_instance_of(String)
      content.should include('2-D seismic imaging@en')
    end

    it "should produce DOT content" do
      content = subject.to_dot
      content.should be_an_instance_of(String)
      content.should include('2-D seismic imaging@en')
    end

    describe "file destination" do
      before { cleanup }

      after { cleanup }

      it "should produce a file" do
        subject.to_file(filename)
        File.should be_exists(filename)
        File.size(filename).should_not be_zero
      end
    end

    private

    def cleanup
      File.delete(filename) if File.exists?(filename)
    end

    def filename
      "test_model.rdf"
    end
  end

  describe "deserialization" do
    it "should return an instance of Model" do
      source = URI("file://#{Redlander.fixture_path('doap.rdf')}")
      subject.from(source, :format => "rdfxml").should be_a Model
    end

    context "from RDF/XML" do
      before { @filename = Redlander.fixture_path("doap.rdf") }

      it "should parse from string" do
        expect {
          subject.from_rdfxml File.read(@filename), :base_uri => "http://rubygems.org/gems/rdf"
        }.to change(subject.statements, :count).by(62)
      end

      it "should parse from URI/file" do
        expect {
          subject.from_rdfxml URI("file://" + @filename), :base_uri => "http://rubygems.org/gems/rdf"
        }.to change(subject.statements, :count).by(62)
      end

      it "should filter statements" do
        filter_object = URI("http://ar.to/#self")
        expect {
          subject.from_rdfxml URI("file://" + @filename), :base_uri => "http://rubygems.org/gems/rdf" do |st|
            st.object.resource? ? st.object.uri != filter_object : true
          end
        }.to change(subject.statements, :count).by(57)
      end
    end

    context "from NTriples" do
      before { @filename = Redlander.fixture_path("doap.nt") }

      it "should parse from string" do
        expect {
          subject.from_ntriples File.read(@filename)
        }.to change(subject.statements, :count).by(62)
      end

      it "should parse from URI/file" do
        expect {
          subject.from_ntriples URI("file://" + @filename)
        }.to change(subject.statements, :count).by(62)
      end
    end

    context "from Turtle" do
      before { @filename = Redlander.fixture_path("doap.ttl") }

      it "should parse from string" do
        expect {
          subject.from_turtle File.read(@filename), :base_uri => "http://rubygems.org/gems/rdf"
        }.to change(subject.statements, :count).by(62)
      end

      it "should parse from URI/file" do
        expect {
          subject.from_turtle URI("file://" + @filename), :base_uri => "http://rubygems.org/gems/rdf"
        }.to change(subject.statements, :count).by(62)
      end
    end
  end

  describe "transactions" do
    before do
      Redland.stub(:librdf_model_transaction_start => 0,
                   :librdf_model_transaction_commit => 0,
                   :librdf_model_transaction_rollback => 0)
    end

    it "should return the output of the block evaluation" do
      subject.transaction { 3+7 }.should eql(10)
    end

    context "when start fails" do
      before { Redland.stub(:librdf_model_transaction_start => -1) }

      it "should not raise RedlandError" do
        lambda {
          subject.transaction { true }
        }.should_not raise_exception RedlandError
      end

      it "should raise RedlandError" do
        expect { subject.transaction_start! }.to raise_exception RedlandError
      end
    end

    context "when commit fails" do
      before { Redland.stub(:librdf_model_transaction_commit => -1) }

      it "should not raise RedlandError" do
        lambda {
          subject.transaction { true }
        }.should_not raise_exception RedlandError
      end

      it "should raise RedlandError" do
        expect { subject.transaction_commit! }.to raise_exception RedlandError
      end
    end

    context "when rollback fails" do
      before { Redland.stub(:librdf_model_transaction_rollback => -1) }

      it "should not raise RedlandError" do
        lambda {
          subject.rollback
        }.should_not raise_exception RedlandError
      end

      it "should raise RedlandError" do
        expect { subject.transaction_rollback! }.to raise_exception RedlandError
      end
    end
  end


  private

  def statement_attributes
    s = URI.parse('http://example.com/concepts#subject')
    p = URI.parse('http://example.com/concepts#label')
    o = "subject!"
    {
      :subject => s,
      :predicate => p,
      :object => o
    }
  end
end
