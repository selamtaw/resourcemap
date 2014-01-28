require 'spec_helper'
require 'active_support/builder' unless defined?(Builder)

describe FacilityXmlGenerator do
	let(:collection) { Collection.make}
	let(:layer) { collection.layers.make }

	# Bad Smell: we need to know how facilities are returned by an ES search to test this.
	let(:facility) {{ "_source" => { "properties" => {} }}}

	let(:xml) { Builder::XmlMarkup.new(:encoding => 'utf-8', :escape => false) }

	def set_facility_attribute(key, value)
		facility["_source"][key] = value
	end

	def facility_properties
		facility["_source"]["properties"]
	end

	describe 'OID generation' do
		it 'should use existing OID annotated field' do
			oid_field = layer.identifier_fields.make.csd_oid!
			facility_properties[oid_field.code] = "oid_value"
			
			generator = FacilityXmlGenerator.new collection
			generator.generate_oid(facility, facility_properties).should eq("oid_value")
		end

		it 'should generate OID from UUID' do
			set_facility_attribute "uuid", "1234-5678-9012-3456"

			generator = FacilityXmlGenerator.new collection
			generator.generate_oid(facility, facility_properties).should eq(generator.to_oid("1234-5678-9012-3456"))
		end
	end

	describe 'Coded Types generation' do
		let(:coded_fruits) {
			coded_fruits = layer.select_one_fields.make(
				config: {
					options: [
						{id: 1, code: "A", label: "Apple"}, 
						{id: 2, code: "B", label: "Banana"},
						{id: 3, code: "P", label: "Peach"}
					]	 
				}.with_indifferent_access
			).csd_coded_type!("fruits")
		}

		let(:coded_supermarkets) {
			coded_supermarkets = layer.select_one_fields.make(
				config: {
					options: [
						{id: 1, code: "C", label: "Carrefour"}, 
						{id: 2, code: "J", label: "Jumbo"}
					] 
				}.with_indifferent_access
			).csd_coded_type!("supermarkets")
		}

		it '' do
			facility_properties[coded_fruits.code] = 'B'
			facility_properties[coded_supermarkets.code] = 'J'			

			generator = FacilityXmlGenerator.new collection

			xml.tag!("root") do
				generator.generate_coded_types xml, facility_properties
			end

			doc = Nokogiri.XML xml

			doc.xpath("//codedType").length.should eq(2)
			
			fruits_xml = doc.xpath("//codedType[@codingSchema='fruits']")
			fruits_xml.attr('code').value.should eq('B')
			fruits_xml.attr('codingSchema').value.should eq('fruits')
			fruits_xml.text.should eq('Banana')

			supermarkets_xml = doc.xpath("//codedType[@codingSchema='supermarkets']")
			supermarkets_xml.attr('code').value.should eq('J')
			supermarkets_xml.attr('codingSchema').value.should eq('supermarkets')
			supermarkets_xml.text.should eq('Jumbo')
		end
	end

	describe 'Other id generation' do
		it '' do
			oid_field = layer.identifier_fields.make.csd_oid!
			other_id_field = layer.identifier_fields.make(config: { "context" => "DHIS", "agency" => "MOH" }.with_indifferent_access)

			facility_properties[other_id_field.code] = 'my_moh_dhis_id'

			generator = FacilityXmlGenerator.new collection

			xml.tag!("root") do
				generator.generate_other_ids xml, facility_properties
			end

			doc = Nokogiri.XML xml

			doc.xpath("//otherID").length.should eq(1)

			other_id = doc.xpath("//otherID[1]")
			other_id.attr('code').value.should eq('my_moh_dhis_id')
			other_id.attr('assigningAuthorityName').value.should eq('MOH')
		end
	end

	describe 'Contact generation' do
		it '' do
			andrew = {
				common_name: layer.text_fields.make.csd_contact_common_name!("Contact 1", "Name 1", "en"),
				forename: layer.text_fields.make.csd_forename!("Contact 1", "Name 1"),
				surname: layer.text_fields.make.csd_surname!("Contact 1", "Name 1"),
				street_address: layer.text_fields.make.csd_address_line!("Contact 1", "Address 1", "streetAddress"),
				city: layer.text_fields.make.csd_address_line!("Contact 1", "Address 1", "city"),
				state_province: layer.text_fields.make.csd_address_line!("Contact 1", "Address 1", "stateProvince"),
				country: layer.text_fields.make.csd_address_line!("Contact 1", "Address 1", "country"),
				postal_code: layer.text_fields.make.csd_address_line!("Contact 1", "Address 1", "postalCode")
			}

			julio = {
				common_name: layer.text_fields.make.csd_contact_common_name!("Contact 2", "Name 1", "en"),
				forename: layer.text_fields.make.csd_forename!("Contact 2", "Name 1"),
				surname: layer.text_fields.make.csd_surname!("Contact 2", "Name 1"),
				street_address: layer.text_fields.make.csd_address_line!("Contact 2", "Address 1", "streetAddress"),
				city: layer.text_fields.make.csd_address_line!("Contact 2", "Address 1", "city"),
				state_province: layer.text_fields.make.csd_address_line!("Contact 2", "Address 1", "stateProvince"),
				country: layer.text_fields.make.csd_address_line!("Contact 2", "Address 1", "country"),
				postal_code: layer.text_fields.make.csd_address_line!("Contact 2", "Address 1", "postalCode")
			}

			facility_properties[andrew[:common_name].code] = "Anderson, Andrew"
			facility_properties[andrew[:forename].code] = "Andrew"
			facility_properties[andrew[:surname].code] = "Anderson"
			facility_properties[andrew[:street_address].code] = "2222 19th Ave SW"
			facility_properties[andrew[:city].code] = "Santa Fe"
			facility_properties[andrew[:state_province].code] = "NM"
			facility_properties[andrew[:country].code] = "USA"
			facility_properties[andrew[:postal_code].code] = "87124"

			facility_properties[julio[:common_name].code] = "Juarez, Julio"
			facility_properties[julio[:forename].code] = "Julio"
			facility_properties[julio[:surname].code] = "Juarez"
			facility_properties[julio[:street_address].code] = "2222 19th Ave SW"
			facility_properties[julio[:city].code] = "Santa Fe"
			facility_properties[julio[:state_province].code] = "NM"
			facility_properties[julio[:country].code] = "USA"
			facility_properties[julio[:postal_code].code] = "87124"

			generator = FacilityXmlGenerator.new collection

			xml.tag!("root") do
				generator.generate_contacts xml, facility_properties
			end

			doc = Nokogiri.XML xml

			doc.xpath("//contact").length.should eq(2)

			doc.xpath("//contact[1]/person/name/commonName[@language='en']").text.should eq("Anderson, Andrew")
			doc.xpath("//contact[1]/person/name/forename").text.should eq("Andrew")
			doc.xpath("//contact[1]/person/name/surname").text.should eq("Anderson")

			doc.xpath("//contact[1]/person/address/addressLine[@component='streetAddress']").text.should eq("2222 19th Ave SW")
			doc.xpath("//contact[1]/person/address/addressLine[@component='city']").text.should eq("Santa Fe")
			doc.xpath("//contact[1]/person/address/addressLine[@component='stateProvince']").text.should eq("NM")
			doc.xpath("//contact[1]/person/address/addressLine[@component='country']").text.should eq("USA")
			doc.xpath("//contact[1]/person/address/addressLine[@component='postalCode']").text.should eq("87124")

			
			doc.xpath("//contact[2]/person/name/commonName[@language='en']").text.should eq("Juarez, Julio")
			doc.xpath("//contact[2]/person/name/forename").text.should eq("Julio")
			doc.xpath("//contact[2]/person/name/surname").text.should eq("Juarez")

			doc.xpath("//contact[2]/person/address/addressLine[@component='streetAddress']").text.should eq("2222 19th Ave SW")
			doc.xpath("//contact[2]/person/address/addressLine[@component='city']").text.should eq("Santa Fe")
			doc.xpath("//contact[2]/person/address/addressLine[@component='stateProvince']").text.should eq("NM")
			doc.xpath("//contact[2]/person/address/addressLine[@component='country']").text.should eq("USA")
			doc.xpath("//contact[2]/person/address/addressLine[@component='postalCode']").text.should eq("87124")
		end
	end

	describe 'language generation' do
		it '' do
			language_config = {
				options: [
					{id: 1, code: "en", label: "English"}, 
					{id: 2, code: "es", label: "Spanish"},
					{id: 3, code: "fr", label: "French"}
				]	 
			}.with_indifferent_access

			language1 = layer.select_one_fields.make(config: language_config).csd_language!("BCP 47")
			language2 = layer.select_one_fields.make(config: language_config).csd_language!("BCP 47")

			facility_properties[language1.code] = "en"
			facility_properties[language2.code] = "es"

			generator = FacilityXmlGenerator.new collection

			xml.tag!("root") do
				generator.generate_languages xml, facility_properties
			end

			doc = Nokogiri.XML xml

			doc.xpath("//language").should have(2).items
			
			language1_xml = doc.xpath("//language[1]")
			language1_xml.attr('code').value.should eq('en')
			language1_xml.attr('codingSchema').value.should eq('BCP 47')
			language1_xml.text.should eq('English')

			language2_xml = doc.xpath("//language[2]")
			language2_xml.attr('code').value.should eq('es')
			language2_xml.attr('codingSchema').value.should eq('BCP 47')
			language2_xml.text.should eq('Spanish')
		end
	end
end