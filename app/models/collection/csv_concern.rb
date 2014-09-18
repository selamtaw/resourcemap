module Collection::CsvConcern
  extend ActiveSupport::Concern

  def csv_template
    CSV.generate do |csv|
      csv << csv_header
      csv << [1, "Site 1", 1.234, 5.678]
      csv << [2, "Site 2", 3.456, 4.567]
    end
  end

  def to_csv(elastic_search_api_results, user, snapshot_id = nil)
    fields = self.visible_fields_for(user, {snapshot_id: snapshot_id})

    CSV.generate do |csv|
      header = ['resmap-id', 'name', 'lat', 'long']
      fields.each do |field|
        if field.hierarchy?
          header << field.code

          # Added one column for each level of the hierarchy
          1.upto(field.hierarchy_max_height) do |i|
            header << "#{field.code}-#{i}"
          end

        else
          header << field.code
        end
      end
      header << 'last updated'
      csv << header

      elastic_search_api_results.each do |result|
        source = result['_source']

        row = [source['id'], source['name'], source['location'].try(:[], 'lat'), source['location'].try(:[], 'lon')]
        fields.each do |field|
          if field.kind == 'yes_no'
            row << (Field.yes?(source['properties'][field.code]) ? 'yes' : 'no')
          elsif field.hierarchy?

            # Add the field's value
            row << source['properties'][field.code]

            ancestors = field.ascendants_of_in_hierarchy(source['properties'][field.code])

            # Add all values
            ancestors.each do |ancestor|
              row << ancestor[:id]
            end

            # Add empty values for the missing elements (if the value is not a leaf)
            (field.hierarchy_max_height - ancestors.count).times do
              row << ""
            end

          else
            row << Array(source['properties'][field.code]).join(", ")
          end
        end
        row << Site.iso_string_to_rfc822(source['updated_at'])
        csv << row
      end
    end
  end

  def sample_csv(user = nil)
    fields = self.visible_fields_for(user, {snapshot_id: nil})

    CSV.generate do |csv|
      header = ['name', 'lat', 'long']
      writable_fields = writable_fields_for(user)
      writable_fields.each { |field| header << field.code }
      csv << header
      row = ['Paris', 48.86, 2.35]
      writable_fields.each do |field|
        row << Array(field.sample_value user).join(", ")
      end
      csv << row
    end
  end

  def import_csv(user, string_or_io)
    Collection.transaction do
      csv = CSV.new string_or_io, return_headers: false

      new_sites = []
      csv.each do |row|
        next unless row[0].present? && row[0] != 'resmap-id'

        site = sites.new name: row[1].strip, user: user
        site.mute_activities = true
        site.lat = row[2].strip if row[2].present?
        site.lng = row[3].strip if row[3].present?
        new_sites << site
      end

      new_sites.each &:save!

      Activity.create! item_type: 'collection', action: 'csv_imported', collection_id: id, user_id: user.id, 'data' => {'sites' => new_sites.length}
    end
  end

  def decode_hierarchy_csv_file(file_path)
    begin
      csv = CSV.read(file_path)

      # Remove empty rows at the end
      while (last = csv.last) && last.all?(&:empty?)
        csv.pop
      end

      decode_hierarchy_csv(csv)
    rescue Exception => ex
      return [{error: ex.message}]
    end
  end

  def decode_hierarchy_csv(csv)

    # First read all items into a hash
    # And validate it's content
    items = validate_format(csv)


    # Add to parents
    items.each do |order, item|
      if item[:parent].present? && !item[:error].present?
        parent_candidates = items.select{|key, hash| hash[:id] == item[:parent]}

        if parent_candidates.any?
          parent = parent_candidates.first[1]
        end

        if parent
          parent[:sub] ||= []
          parent[:sub] << item
        end
      end
    end


    # Remove those that have parents, and at the same time delete their parent key
    items = items.reject do |order, item|
      if item[:parent] && !item[:error].present?
        item.delete :parent
        true
      else
        false
      end
    end

    items.values
  end

  def generate_error_description_list(hierarchy_csv)
    hierarchy_errors = []
    hierarchy_csv.each do |item|
      message = ""

      if item[:error]
        message << "Error: #{item[:error]}"
        message << " " + item[:error_description] if item[:error_description]
        message << " in line #{item[:order]}." if item[:order]
      end

      hierarchy_errors << message if !message.blank?
    end
    hierarchy_errors.join("<br/>").to_s
  end

  def validate_format(csv)
    i = 0
    items = {}
    csv.each do |row|
      item = {}
      if row[0] == 'ID'
        next
      else
        i = i+1
        item[:order] = i

        if !(row.length == 3 || row.length == 4)
          item[:error] = "Wrong format."
          item[:error_description] = "Invalid column number"
        else

          name = row[2].strip

          #Check unique id
          id = row[0].strip
          if items.any?{|item| item.second[:id] == id}
            item[:error] = "Invalid id."
            item[:error_description] = "Hierarchy id should be unique"
            error = true
          end

          #Check parent id exists
          parent_id = row[1]
          if(parent_id.present? && !csv.any?{|csv_row| csv_row[0].strip == parent_id.strip})
            item[:error] = "Invalid parent value."
            item[:error_description] = "ParentID should match one of the Hierarchy ids"
            error = true
          end

          if !error
            item[:id] = id
            item[:parent] = row[1].strip if row[1].present?
            item[:name] = name
            item[:type] = row[3].strip if row[3].present?
          end
        end

        items[item[:order]] = item
      end
    end
    items
  end

  private

  def csv_header
    ["Site ID", "Name", "Lat", "Lng"]
  end
end
