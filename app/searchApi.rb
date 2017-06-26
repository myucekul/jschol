require 'aws-sdk'
require 'sequel'
require 'json'
require 'pp'

# API to connect to AWS CloudSearch
$csClient = Aws::CloudSearchDomain::Client.new(
  endpoint: YAML.load_file("config/cloudSearch.yaml")["searchEndpoint"])

# key is escholarship UI/aws field value in all instances except pub_year (aws field value)
# value is a hash {displayName, awsFacetParam, filterTransform, facetTransform}
# awsFacetParam is either {buckets: [<list of strings>]} or {sort: 'count', size: 100}
# this is the parameter specifying how to retrieve the facet list from aws
# filterTransform takes selected filter values from escholarship UI 'params' & augments with display values
# facetTransform takes facet values returned from aws cloudsearch facet results & augments with display values

# TODO: could potentially add a mapping from aws field to escholarship UI field
# further abstracting 'pub_year' vs. 'pub_year_start' and 'pub_year_end'
# in all other instances besides pub_year (type_of_work, supp_file_types, peer_reviewed, etc) 
# the escholarship UI field remains the same, though

# TODO: the extent stats are still being generated by a separate search function 
# that should maybe get folded up into the main search function
# search would need to be modified to understand what to do without a query parameter (matchall & structured)
# search would also need to be modified to not necessarily do all the results handling

FACETS = {
  'type_of_work' => {
    'displayName' => 'Type of Work', 
    'awsFacetParam' => {buckets: ['article', 'monograph', 'dissertation', 'multimedia']},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal, 'displayName' => TYPE_OF_WORK[filterVal]} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => TYPE_OF_WORK[facetVal['value']]} } }
  },
  'peer_reviewed' => {
    'displayName' => 'Peer Review',
    'awsFacetParam' => {buckets: [1]},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => 'Peer-reviewed only'} } }
  },
  'supp_file_types' => {
    'displayName' => 'Included Media',
    'awsFacetParam' => {buckets: ['video', 'audio', 'images', 'zip', 'other files']},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal, 'displayName' => filterVal.capitalize} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => facetVal['value'].capitalize } } },
  },
  'pub_year' => {
    'displayName' => 'Publication Year',
    'awsFacetParam' => {sort: 'count', size: 100},
    'filterTransform' => lambda do |year_start, year_end| 
      if year_start and year_end
        return [{'value' => "#{year_start}-#{year_end}"}]
      elsif year_start
        return [{'value' => year_start }]
      elsif year_end
        return [{'value' => year_end }]
      end
    end,
    'facetTransform' => lambda { |year_start, year_end| {pub_year_start: year_start, pub_year_end: year_end} }
  },
  # per message from Lisa 9/13/2016 regarding campus facets:
  #   - lbnl should be lbl (unsure if it should be LBL in the display too?)
  #   - ANR (Agriculture and Natural Resources) should be added to this list
  'campuses' => {
    'displayName' => 'Campus',
    'awsFacetParam' => {buckets: ['ucb', 'ucd', 'uci', 'ucla', 'ucm', 'ucr', 'ucsd', 'ucsf', 'ucsb', 'ucsc', 'ucop', 'lbnl']},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal, 'displayName' => get_unit_display_name(filterVal)} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => get_unit_display_name(facetVal['value'])} } }
  },
  'departments' => {
    'displayName' => 'Department',
    'awsFacetParam' => {sort: 'count', size: 100},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal, 'displayName' => get_unit_display_name(filterVal)} } },
    'facetTransform' => lambda { |facetVals| get_unit_hierarchy(facetVals) }
  },
  'journals' => {
    'displayName' => 'Journal',
    'awsFacetParam' => {sort: 'count', size: 100},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal, 'displayName' => get_unit_display_name(filterVal)} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => get_unit_display_name(facetVal['value'])} } }
  },
  'disciplines' => {
    'displayName' => 'Discipline',
    'awsFacetParam' => {sort: 'count', size: 100},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count']} } }
  },
  'rights' => {
    'displayName' => 'Reuse License',
    'awsFacetParam' => {sort: 'count', size: 100},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| if filterVal == 'public' then {'value' => filterVal, 'displayName' => 'Public'} else {'value' => filterVal} end } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => RIGHTS[facetVal['value']]} } }
  },
  'series' => {
    'displayName' => 'Series',
    'awsFacetParam' => {sort: 'count', size: 100},
    'filterTransform' => lambda { |filterVals| filterVals.map { |filterVal| {'value' => filterVal, 'displayName' => get_unit_display_name(filterVal)} } },
    'facetTransform' => lambda { |facetVals| facetVals.map { |facetVal| {'value' => facetVal['value'], 'count' => facetVal['count'], 'displayName' => get_unit_display_name(facetVal['value'])} } }
  }
}

# key is code that escholarship UI uses, value is code that AWS uses
SORT = {
  'rel' => '_score desc', 
  'pop' => '_score desc', 
  'a-title' => 'title asc', 
  'z-title' => 'title desc', 
  'a-author' => 'sort_author asc',
  'z-author' => 'sort_author desc',
  'asc' => 'pub_date asc',
  'desc' => 'pub_date desc',
  'default' => '_score desc'
}

# key is code that escholarship UI/AWS uses, value is Display Name
RIGHTS = {
  'public' => 'Public',
  'CC BY' => 'BY - Attribution required',
  'CC BY-SA' => 'BY-SA - Attribution; Derivatives must use same license',
  'CC BY-ND' => 'BY-ND - Attribution; No derivatives',
  'CC BY-NC' => 'BY-NC - Attribution; NonCommercial use only',
  'CC BY-NC-SA' => 'BY-NC-SA - Attribution; NonCommercial use; Derivatives use same license',
  'CC BY-NC-ND' => 'BY-NC-ND - Attribution; NonCommercial use; No derivatives'
}

# key is code that escholarship UI/AWS uses, value is DisplayName
TYPE_OF_WORK = {
  'article' => 'Article',
  'monograph' => 'Book',
  'dissertation' => 'Theses',
  'multimedia' => 'Multimedia'
}

# takes the code that escholarship UI/AWS uses, returns DisplayName
def get_unit_display_name(unitID)
  unit = $unitsHash[unitID]
  unit ? unit.name : "null"
end

# takes list of facets in [{value: , count: }] form where value is the value that escholarship UI/AWS uses.
# returns a nested hierarchy list: [{value, count, displayName, (optionally) descendents: []}, ...]
def get_unit_hierarchy(unitFacets)
  idToUnitFacet = Hash[unitFacets.map { |unitFacet| [unitFacet['value'], unitFacet] }]
  for unitFacet in unitFacets
    unit = $unitsHash[unitFacet['value']]
    unitFacet['displayName'] = unit.name

    # get the direct ancestor to this oru unit if the ancestor is also an oru
    ancestor_id = $oruAncestors[unit.id]
    if ancestor_id
      # check that this ancestor is already in the facet list
      u = idToUnitFacet[ancestor_id]
      if u
        if u.key? 'descendents'
          u['descendents'].push(unitFacet)
        else
          u['descendents'] = [unitFacet]
        end
      else
        # Ancestor not in list - this can happen when the number of departments exceeds
        # the max facet query (typically 100). In this case, leave out the child unit.
        puts "Note: some child depts omitted because ancestor not present (likely cut off by facet query)."
      end
      unitFacet['ancestor_in_list'] = true
    end
  end

  unitFacets.select! { |unitFacet| !unitFacet['ancestor_in_list'] }
end

def get_query_display(params)
  #Augment filters and filter values with display names
  filters = {}
  params.each do |field, filterValues|
    if FACETS.keys.include? field then
      filters[field] = {
        'display': FACETS[field]['displayName'],
        'fieldName' => field,
        'filters' => FACETS[field]['filterTransform'].call(filterValues)
      }
    end
  end

  #Add pub_year to filter list
  if params.dig('pub_year_start', 0) || params.dig('pub_year_end', 0)
    filters['pub_year'] = {
      'display' => FACETS['pub_year']['displayName'],
      'fieldName' => 'pub_year',
      'filters' => FACETS['pub_year']['filterTransform'].call(params['pub_year_start'][0], params['pub_year_end'][0])
    }
  end
    
  display_params = {
    'q' => params['q'] ? params['q'].join(" ") : '',
    'rows' => params.dig('rows', 0) ? params['rows'][0] : '10',
    'sort' => params.dig('sort', 0) ? params['sort'][0] : 'rel',
    'start' => params.dig('start', 0) ? params['start'][0] : '0',
    'filters' => filters
  }
end

def aws_encode(params, facetTypes)
  aws_params = {
    query: params.has_key?('q') ? params['q'].join(" ") : 'matchall',
    size: params.dig('rows', 0) ? params['rows'][0] : 10,
    sort: params.dig('sort', 0) ? SORT[params['sort'][0]] : '_score desc',
    start: params.dig('start', 0) ? params['start'][0] : 0,
  }

  if aws_params[:query] == 'matchall' then aws_params[:query_parser] = "structured" end

  # create facet query, only create facet query for fields specified in facetTypes
  facetQuery = {}
  facetTypes.each { |facetType| facetQuery[facetType] = FACETS[facetType]['awsFacetParam'] }

  if !facetQuery.empty? then aws_params[:facet] = JSON.generate(facetQuery) end

  # create filter queries, always apply filters for all available fields in cloudsearch
  filterQuery = []
  FACETS.each do |field, behavior|
    if params.keys.include? field then
      filters = params[field].map { |filter| "#{field}: '#{filter}'" }
      if filters.length > 1 then filters = "(or #{filters.join(" ")})" end
      filterQuery << filters
    end
  end

  # add pub_year to filter query
  if params.dig('pub_year_start', 0) || params.dig('pub_year_end', 0)
    date_range = params.dig('pub_year_start', 0) ? "[#{params['pub_year_start'][0]}," : "{,"
    date_range = params.dig('pub_year_end', 0) ? "#{date_range}#{params['pub_year_end'][0]}]" : "#{date_range}}"
    filterQuery.push("pub_year: #{date_range}")
  end

  # join filter query
  if filterQuery.length > 1 then filterQuery = "(and #{filterQuery.join(" ")})" end
  if filterQuery.length == 1 then filterQuery = filterQuery.join(" ") end
  if filterQuery.length > 0 then aws_params[:filter_query] = filterQuery end

  return aws_params
end

def facet_secondary_query(params, field_type)
  params.delete(field_type)
  aws_params = aws_encode(params, [field_type])
  response = normalizeResponse($csClient.search(return: '_no_fields', **aws_params))
  return response['facets'][field_type]
end

def normalizeResponse(response)
  if response.instance_of? Array
    response.map { |v| normalizeResponse(v) }
  elsif response.respond_to?(:map)
    response.to_h.map { |k,v| [k.to_s, normalizeResponse(v)] }.to_h
  elsif response.nil? || response.is_a?(String) || response.is_a?(Integer)
    response
  else
    raise "Unexpected response type: #{response.inspect}"
  end
end

def search(params, facetTypes=FACETS.keys)
  aws_params = aws_encode(params, facetTypes)
  response = normalizeResponse($csClient.search(return: '_no_fields', **aws_params))

  # augment search result items with more item-specific data
  if response['hits'] && response['hits']['hit']
    itemIds = response['hits']['hit'].map { |item| item['id'] }
    itemData = readItemData(itemIds)
    searchResults = itemResultData(itemIds, itemData, ['thumbnail', 'pub_year', 'publication_information', 'type_of_work', 'rights', 'peer_reviewed'])
  end
  
  facetHash = response['facets']
  facets = []
  
  # Get facet lists, check against list of all available aws fields
  if facetHash
    FACETS.keys.each do |field_type|
      # Make sure the field type is actually in the facet hash returned from aws
      if facetHash.key?(field_type)
        if field_type != 'pub_year' && params.key?(field_type) 
          facetHash[field_type] = facet_secondary_query(params.clone, field_type)
        end

        facetBundle = {'display' => FACETS[field_type]['displayName'],
          'fieldName' => field_type
        }

        if field_type != 'pub_year'
          facetBundle['facets'] = FACETS[field_type]['facetTransform'].call(facetHash[field_type]['buckets'])
        else
          facetBundle['range'] = FACETS[field_type]['facetTransform'].call(params['pub_year_start'][0], params['pub_year_end'][0])
        end

        facets << facetBundle
      end
    end
  end
    
  return {'count' => response['hits']['found'], 'query' => get_query_display(params.clone), 'searchResults' => searchResults, 'facets' => facets}
end

def extent(id, type)
  aws_params =
  {
    query: "matchall",
    query_parser: "structured",
    facet: JSON.generate({
      'pub_year' => FACETS['pub_year']['awsFacetParam'],
      }),
    size: 0
  }
  if (type == 'oru') then
    aws_params[:filter_query] = "(term field=departments '#{id}')"
  elsif (type == 'journal') then 
    aws_params[:filter_query] = "(term field=journals '#{id}')"
  elsif (type == 'campus') then
    aws_params[:filter_query] = "(term field=campuses '#{id}')"
  elsif (type == 'series' || type == 'monograph_series' || type == 'seminar_series') then 
    aws_params[:filter_query] = "(term field=series '#{id}')"
  else 
    raise("Not a valid unit type.")
  end
  response = normalizeResponse($csClient.search(return: '_no_fields', **aws_params))
  pb = response['facets']['pub_year']['buckets']
  pub_years = pb.empty? ? [{"value"=>"0"}, {"value"=>"0"}] : pb.sort_by { |bucket| Integer(bucket['value']) }
  return {:count => response['hits']['found'], :pub_year => {:start => pub_years[0]['value'], :end => pub_years[-1]['value']}}
end  
