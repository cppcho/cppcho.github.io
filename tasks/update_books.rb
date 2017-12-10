require 'yaml'
require 'amazon/ecs'

THOTTLE_RATE = 10

output_path = File.join(__dir__, '../_data/books.yml')
api_config_path = File.join(__dir__, '../_config/api.yml')
books_config_path = File.join(__dir__, '../_config/books.yml')

api_config = YAML.load_file(api_config_path)
amazon_config = api_config["amazon"]
books_config = YAML.load_file(books_config_path)

Amazon::Ecs.configure do |options|
  options[:AWS_access_key_id] = amazon_config["access_key"]
  options[:AWS_secret_key] = amazon_config["secret_key"]
  options[:associate_tag] = amazon_config["associate_id"]
end

# Gather all item ids from books.yml
item_ids = [
  books_config["reading"],
  books_config["read"].map do |i|
    i["items"]
  end
].flatten

raise "No book items in config!" if item_ids.empty?

# Final output to be exported to yaml file
book_mappings = {}

item_ids.each_slice(10) do |a|
  puts "Fetch from Amazon .."
  resp = Amazon::Ecs.item_lookup(a.join(','), country: 'jp', response_group: 'ItemAttributes,ItemIds')

  raise resp.error if resp.has_error?

  resp.items.each do |item|
    item_attributes = item.get_element('ItemAttributes')
    book_mappings[item.get('ASIN')] = {
      "title" => item_attributes.get('Title'),
      "authors" => item_attributes.get_array('Author'),
      "url" => item.get('DetailPageURL'),
    }
  end

  sleep THOTTLE_RATE
end

# Ouput to _data/books.yml
output = {
  "reading" => [],
  "read" => []
}

books_config["reading"].each do |asin|
  puts "ASIN #{asin} not available" unless book_mappings[asin]
  output["reading"].push(book_mappings[asin])
end

books_config["read"].each do |item|
  arr = []
  item["items"].each do |asin|
    puts "ASIN #{asin} not available" unless book_mappings[asin]
    arr.push(book_mappings[asin])
  end
  output["read"].push({
    "year" => item["year"],
    "items" => arr
  })
end

output_file = File.open(output_path, "w")
output_file << output.to_yaml
output_file.close

puts "Done"
