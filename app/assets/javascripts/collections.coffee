@initCollections = ->
  SITES_PER_PAGE = 25

  Cluster = (map, cluster) ->
    @position = new google.maps.LatLng(cluster.lat, cluster.lng)
    @count = cluster.count
    @map = map
    @setMap map
    @maxZoom = cluster.max_zoom

  Cluster.prototype = new google.maps.OverlayView

  Cluster.prototype.onAdd = ->
    @div = document.createElement 'DIV'
    @div.className = 'cluster'
    @div.innerText = (@count).toString()

    [@image, @width, @height] = if @count < 10
                                  [1, 53, 52]
                                else if @count < 25
                                  [2, 56, 55]
                                else if @count < 50
                                  [3, 66, 65]
                                else if @count < 100
                                  [4, 78, 77]
                                else
                                  [5, 90, 89]

    @div.style.backgroundImage = "url('http://google-maps-utility-library-v3.googlecode.com/svn/trunk/markerclusterer/images/m#{@image}.png')"
    @div.style.width = "#{@width}px"
    @div.style.height = @div.style.lineHeight = "#{@height}px"

    @getPanes().overlayMouseTarget.appendChild @div

    @listener = google.maps.event.addDomListener @div, 'click', =>
      @map.panTo(@position)
      nextZoom = (if @maxZoom then @maxZoom else @map.getZoom()) + 1
      @map.setZoom nextZoom

  Cluster.prototype.draw = ->
    pos = @getProjection().fromLatLngToDivPixel @position
    @div.style.left = "#{pos.x - @width / 2}px"
    @div.style.top = "#{pos.y - @height / 2}px"

  Cluster.prototype.onRemove = ->
    google.maps.event.removeListener @listener
    @div.parentNode.removeChild @div
    delete @div

  class Field
    constructor: (data) ->
      @code = ko.observable data?.code
      @name = ko.observable data?.name
      @kind = ko.observable data?.kind
      @value = ko.observable()
      @valueUI = ko.computed => if @value() then @value() else '(no value)'
      @editing = ko.observable false

  class SitesContainer
    constructor: (data) ->
      @id = ko.observable data?.id
      @name = ko.observable data?.name
      @lat = ko.observable data?.lat
      @lng = ko.observable data?.lng
      @position = ko.computed
        read: => if @lat() && @lng() then new google.maps.LatLng(@lat(), @lng()) else null
        write: (latLng) => @lat(latLng.lat()); @lng(latLng.lng())
        owner: @
      @sites = ko.observableArray()
      @expanded = ko.observable false
      @sitesPage = 1
      @hasMoreSites = ko.observable true
      @loadingSites = ko.observable false
      @siteIds = {}

    loadMoreSites: (callback) =>
      if @hasMoreSites()
        @loadingSites true
        # Fetch more sites. We fetch one more to know if we have more pages, but we discard that
        # extra element so the user always sees SITES_PER_PAGE elements.
        $.get @sitesUrl(), {offset: (@sitesPage - 1) * SITES_PER_PAGE, limit: SITES_PER_PAGE + 1}, (data) =>
          @sitesPage += 1
          if data.length == SITES_PER_PAGE + 1
            data.pop()
          else
            @hasMoreSites false
          for site in data
            @addSite new Site(this, site)
          @loadingSites false
          callback() if callback && typeof(callback) == 'function'
      else
        callback() if callback && typeof(callback) == 'function'

    addSite: (site) =>
      unless @siteIds[site.id()]
        @sites.push(site)
        @siteIds[site.id()] = site

    toggle: =>
      # Load more sites when we expand, but only the first time
      if @group() && !@expanded() && @hasMoreSites() && @sitesPage == 1
        @loadMoreSites()
      @expanded(!@expanded())

  class Collection extends SitesContainer
    constructor: (data) ->
      super(data)
      @class = 'Collection'
      @fields = ko.observableArray()
      @checked = ko.observable true
      @fieldsInitialized = false

    sitesUrl: -> "/collections/#{@id()}/sites"

    level: -> 0

    fetchLocation: =>
      $.get "/collections/#{@id()}.json", {}, (data) =>
        @lat(data.lat); @lng(data.lng)

    fetchFields: =>
      unless @fieldsInitialized
        @fieldsInitialized = true
        $.get "/collections/#{@id()}/fields", {}, (data) =>
          @fields $.map(data, (x) => new Field(x))

    findFieldByCode: (code) =>
      (field for field in @fields() when field.code() == code)[0]

    clearFieldValues: =>
      field.value(null) for field in @fields()

  class Site extends SitesContainer
    constructor: (parent, data) ->
      super(data)
      @class = 'Site'
      @parent = parent
      @selected = ko.observable()
      @id = ko.observable data?.id
      @parent_id = ko.observable data?.parent_id
      @group = ko.observable data?.group
      @name = ko.observable data?.name
      @locationMode = ko.observable data?.location_mode
      @properties = ko.observable data?.properties
      @editingName = ko.observable(false)
      @editingLocation = ko.observable(false)
      @locationText = ko.computed
        read: =>
          (Math.round(@lat() * 100000) / 100000) + ', ' + (Math.round(@lng() * 100000) / 100000)
        write: (value) =>
          @locationTextTemp = value
        owner: @
      @locationTextTemp = @locationText()

    sitesUrl: -> "/sites/#{@id()}/root_sites"

    level: =>
      @parent.level() + 1

    hasLocation: =>
      @position() && !(@group() && @locationMode() == 'none')

    fetchLocation: =>
      $.get "/sites/#{@id()}.json", {}, (data) =>
        @lat(data.lat); @lng(data.lng)
      @parent.fetchLocation()

    updateProperty: (code, value) =>
      @properties()[code] = value
      $.post "/sites/#{@id()}/update_property", {code: code, value: value}, =>

    copyPropertiesFromCollection: (collection) =>
      @properties({})
      for field in collection.fields()
        @properties()[field.code()] = field.value()

    copyPropertiesToCollection: (collection) =>
      collection.clearFieldValues()
      if @properties()
        for key, value of @properties()
          collection.findFieldByCode(key).value(value)

    toJSON: =>
      json =
        id: @id()
        group: @group()
        name: @name()
      json.lat = @lat() if @lat()
      json.lng = @lng() if @lng()
      json.parent_id = @parent_id() if @parent_id()
      json.properties = @properties() if @properties()
      json.location_mode = @locationMode() if @locationMode()
      json

  class CollectionViewModel
    constructor: (collections, lat, lng) ->
      self = this

      @collections = ko.observableArray $.map(collections, (x) -> new Collection(x))
      @currentCollection = ko.observable()
      @currentParent = ko.observable()
      @editingSite = ko.observable()
      @selectedSite = ko.observable()
      @newSite = ko.computed => if @editingSite() && !@editingSite().id() && !@editingSite().group() then @editingSite() else null
      @newGroup = ko.computed => if @editingSite() && !@editingSite().id() && @editingSite().group() then @editingSite() else null
      @showSite = ko.computed => if @editingSite()?.id() && !@editingSite().group() then @editingSite() else null
      @showGroup = ko.computed => if @editingSite()?.id() && @editingSite().group() then @editingSite() else null
      @collectionsCenter = new google.maps.LatLng(lat, lng)
      @markers = {}
      @clusters = {}
      @reloadMapSitesAutomatically = true
      @reuseCurrentClusters = true
      @requestNumber = 0
      @geocoder = new google.maps.Geocoder();

      @markerImageInactive = new google.maps.MarkerImage(
        "/assets/marker_sprite_inactive.png", new google.maps.Size(20, 34), new google.maps.Point(0, 0), new google.maps.Point(10, 34)
      )
      @markerImageInactiveShadow = new google.maps.MarkerImage(
        "/assets/marker_sprite_inactive.png", new google.maps.Size(37, 34), new google.maps.Point(20, 0), new google.maps.Point(10, 34)
      )
      @markerImageTarget = new google.maps.MarkerImage(
        "/assets/marker_sprite_target.png", new google.maps.Size(20, 34), new google.maps.Point(0, 0), new google.maps.Point(10, 34)
      )
      @markerImageTargetShadow = new google.maps.MarkerImage(
        "/assets/marker_sprite_target.png", new google.maps.Size(37, 34), new google.maps.Point(20, 0), new google.maps.Point(10, 34)
      )

      Sammy( ->
        @get '#:collection', ->
          collection = self.findCollectionById(parseInt this.params.collection)
          initialized = self.initMap(collection)

          collection.loadMoreSites() if collection.sitesPage == 1
          collection.fetchFields()

          self.currentCollection collection

          unless initialized
            self.reloadMapSitesAutomatically = false
            self.reuseCurrentClusters = false
            self.map.panTo(collection.position()) if collection.position()
            self.reloadMapSites()

        @get '', ->
          initialized = self.initMap()
          self.currentCollection(null)
          self.reloadMapSites() unless initialized
      ).run()

      $.each @collections(), (idx) =>
        @collections()[idx].checked.subscribe (newValue) =>
          @reuseCurrentClusters = false
          @reloadMapSites()

    findCollectionById: (id) =>
      (x for x in @collections() when x.id() == id)[0]

    goToRoot: ->
      location.hash = ''

    enterCollection: (collection) ->
      location.hash = "#{collection.id()}"

    editCollection: (collection) ->
      window.location = "/collections/#{collection.id()}"

    createCollection: ->
      window.location = "/collections/new"

    createGroup: =>
      @createSiteOrGroup true

    createSite: =>
      @createSiteOrGroup false

    createSiteOrGroup: (group) =>
      parent = if @selectedSite() then @selectedSite() else @currentCollection()
      pos = @originalSiteLocation = @map.getCenter()
      site = if group
               new Site(parent, parent_id: @selectedSite()?.id(), lat: pos.lat(), lng: pos.lng(), group: group, location_mode: 'auto')
             else
               new Site(parent, parent_id: @selectedSite()?.id(), lat: pos.lat(), lng: pos.lng(), group: group)
      @editingSite site
      @editingSite().copyPropertiesToCollection(@currentCollection()) unless @editingSite().group()

      # Add a marker to the map for setting the site's position
      if group
        @subscribeToLocationModeChange site
      else
        @createMarkerForSite site

    createMarkerForSite: (site, drop = false) =>
      @deleteMarker()

      draggable = site.group() || site.editingLocation()
      @marker = new google.maps.Marker
        map: @map
        position: site.position()
        animation: if drop || !site.id() then google.maps.Animation.DROP else null
        draggable: draggable
        icon: @markerImageTarget
        shadow: @markerImageTargetShadow
      @setupMarkerListener site, @marker
      @setAllMarkersInactive() if draggable

    subscribeToLocationModeChange: (site) =>
      @subscription = site.locationMode.subscribe (newLocationMode) =>
        if newLocationMode == 'manual'
          @createMarkerForSite site, true
        else
          @deleteMarker()

    unsubscribeToLocationModeChange: =>
      if @subscription
        @subscription.dispose()
        delete @subscription

    editSite: (site) =>
      site.copyPropertiesToCollection(@currentCollection())
      @selectSite(site) unless @selectedSite() && @selectedSite().id() == site.id()
      @editingSite(site)

    editSiteName: =>
      @editingSite().editingName(true)
      @originalSiteName = @editingSite().name()

    siteNameKeyPress: (site, event) =>
      switch event.keyCode
        when 13 then @saveSiteName()
        when 27 then @exitSiteName()
        else true

    saveSiteName: =>
      @editingSite().editingName(false)
      json = {site: {name: @editingSite().name()}, _method: 'put'}
      $.post "/collections/#{@currentCollection().id()}/sites/#{@editingSite().id()}.json", json, (data) =>

    exitSiteName: =>
      @editingSite().name(@originalSiteName)
      @editingSite().editingName(false)
      delete @originalSiteName

    editSiteLocation: =>
      @originalSiteLocation = @editingSite().position()
      @editingSite().editingLocation(true)
      @marker.setDraggable(true)
      @setAllMarkersInactive()
      @reloadMapSitesAutomatically = false
      @reuseCurrentClusters = false
      @map.panTo(@editingSite().position())
      @reloadMapSites()

    siteLocationKeyPress: (site, event) =>
      switch event.keyCode
        when 13 then @saveSiteLocation()
        when 27 then @exitSiteLocation()
        else true

    saveSiteLocation: =>
      @editingSite().editingLocation(false)
      @setAllMarkersActive()

      save = =>
        json = {site: {lat: @editingSite().lat(), lng: @editingSite().lng()}, _method: 'put'}
        $.post "/collections/#{@currentCollection().id()}/sites/#{@editingSite().id()}.json", json, (data) =>
          @editingSite().lat(data.lat)
          @editingSite().lng(data.lng)
          @editingSite().parent.fetchLocation()
          @marker.setPosition(@editingSite().position())
          @reuseCurrentClusters = false
          @map.panTo(@editingSite().position())
          @reloadMapSites()

      if match = @editingSite().locationTextTemp.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/)
        @editingSite().lat(parseFloat(match[1]))
        @editingSite().lng(parseFloat(match[2]))
        save()
      else
        @geocoder.geocode { 'address': @editingSite().locationTextTemp}, (results, status) =>
          if results.length > 0
            @editingSite().position(results[0].geometry.location)
            save()
          else
            @editingSite().position(@originalSiteLocation)

    newSiteLocationKeyPress: (site, event) =>
      switch event.keyCode
        when 13
          @moveSiteLocation()
          false
        else true

    moveSiteLocation: =>
      if match = @editingSite().locationTextTemp.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/)
        @editingSite().lat(parseFloat(match[1]))
        @editingSite().lng(parseFloat(match[2]))
        @marker.setPosition(@editingSite().position())
        @map.panTo(@editingSite().position())
      else
        @geocoder.geocode { 'address': @editingSite().locationTextTemp}, (results, status) =>
          if results.length > 0
            @editingSite().position(results[0].geometry.location)
          else
            @editingSite().position(@originalSiteLocation)
          @marker.setPosition(@editingSite().position())
          @map.panTo(@editingSite().position())

    exitSiteLocation: =>
      @marker.setPosition(@originalSiteLocation)
      @editingSite().editingLocation(false)
      @setAllMarkersActive()
      delete @originalSiteLocation

    saveSite: =>
      callback = (data) =>
        unless @editingSite().id()
          @editingSite().id(data.id)
          if @selectedSite()
            @selectedSite().addSite(@editingSite())
          else
            @currentCollection().addSite(@editingSite())

        # If lat/lng/locationMode changed, update parent locations from server
        if @editingSite().lat() != data.lat || @editingSite().lng() != data.lng || (@editingSite().group() && @editingSite().locationMode() != data.location_mode)
          @editingSite().parent.fetchLocation()

        @editingSite().lat(data.lat)
        @editingSite().lng(data.lng)

        @exitSite()

      unless @editingSite().group()
        @editingSite().copyPropertiesFromCollection(@currentCollection())

      json = {site: @editingSite().toJSON()}

      if @editingSite().id()
        json._method = 'put'
        $.post "/collections/#{@currentCollection().id()}/sites/#{@editingSite().id()}.json", json, callback
      else
        $.post "/collections/#{@currentCollection().id()}/sites", json, callback

    exitSite: =>
      @unsubscribeToLocationModeChange()
      @editingSite().editingLocation(false)
      @deleteMarker() unless @editingSite().id()
      @editingSite(null)

    selectSite: (site) =>
      if @selectedSite() == site
        if !site.group() && @markers[site.id()]
          @setMarkerIcon @markers[site.id()], 'active'
        @selectedSite().selected(false)
        @selectedSite(null)
        @deleteMarker()
        @reuseCurrentClusters = false
        @reloadMapSites()
      else
        oldSiteId = @selectedSite()?.id()
        @selectedSite().selected(false) if @selectedSite()
        @selectedSite(site)
        @selectedSite().selected(true)
        if @selectedSite().id() && @selectedSite().hasLocation()
          @reloadMapSitesAutomatically = false
          @reuseCurrentClusters = false
          if @selectedSite().group()
            @deleteMarker()
          else
            @createMarkerForSite @selectedSite()
          @map.panTo(@selectedSite().position())
          @reloadMapSites =>
            if oldSiteId && @markers[oldSiteId]
              @setMarkerIcon @markers[oldSiteId], 'active'
            if !@selectedSite().group() && @markers[@selectedSite().id()]
              @setMarkerIcon @markers[@selectedSite().id()], 'target'

    toggleSite: (site) =>
      site.toggle()

    editFieldValue: (field) =>
      @currentField = field
      @originalFieldValue = field.value()
      @currentField.editing(true)

    fieldKeyPress: (field, event) =>
      switch event.keyCode
        when 13 then @saveFieldValue()
        when 27 then @exitField()
        else true

    exitField: =>
      @currentField.value(@originalFieldValue)
      @currentField.editing(false)

    saveFieldValue: =>
      @currentField.editing(false)
      @editingSite().updateProperty(@currentField.code(), @currentField.value())
      delete @currentField

    initMap: (collection) =>
      return false if @map

      mapOptions =
        center: if collection?.position() then collection.position() else @collectionsCenter
        zoom: 4
        mapTypeId: google.maps.MapTypeId.ROADMAP
      @map = new google.maps.Map document.getElementById("map"), mapOptions

      listener = google.maps.event.addListener @map, 'bounds_changed', =>
        google.maps.event.removeListener listener
        @reloadMapSites()

      google.maps.event.addListener @map, 'dragend', => @reloadMapSites()
      google.maps.event.addListener @map, 'zoom_changed', =>
        listener2 = google.maps.event.addListener @map, 'bounds_changed', =>
          google.maps.event.removeListener listener2
          @reloadMapSites() if @reloadMapSitesAutomatically

      true

    reloadMapSites: (callback) =>
      bounds = @map.getBounds()

      # Wait until map is loaded
      unless bounds
        setTimeout(( => @reloadMapSites(callback)), 100)
        return

      ne = bounds.getNorthEast()
      sw = bounds.getSouthWest()
      collection_ids = if @currentCollection()
                         [@currentCollection().id()]
                       else
                          c.id for c in @collections() when c.checked()
      query =
        n: ne.lat()
        s: sw.lat()
        e: ne.lng()
        w: sw.lng()
        z: @map.getZoom()
        collection_ids: collection_ids
        exclude_id: if @selectedSite()?.id() && !@selectedSite().group() then @selectedSite().id() else null

      @requestNumber += 1
      currentRequestNumber = @requestNumber

      getCallback = (data = {}) =>
        return unless currentRequestNumber == @requestNumber

        @drawSitesInMap data.sites
        @drawClustersInMap data.clusters
        @reloadMapSitesAutomatically = true

        callback() if callback && typeof(callback) == 'function'

      if query.collection_ids.length == 0
        # Save a request to the server if there are no selected collections
        getCallback()
      else
        $.get "/sites/search.json", query, getCallback

    drawSitesInMap: (sites = []) =>
      dataSiteIds = {}
      editingSiteId = if @editingSite()?.id() && @editingSite().editingLocation() then @editingSite().id() else null
      selectedSiteId = @selectedSite()?.id()

      # Add markers if they are not already on the map
      for site in sites
        dataSiteIds[site.id] = site.id
        unless @markers[site.id]
          markerOptions =
            map: @map
            position: new google.maps.LatLng(site.lat, site.lng)
          # Show site in grey if editing a site (but not if it's the one being edited)
          if editingSiteId && editingSiteId != site.id
            markerOptions.icon = @markerImageInactive
            markerOptions.shadow = @markerImageInactiveShadow
          if selectedSiteId && selectedSiteId == site.id
            markerOptions.icon = @markerImageTarget
            markerOptions.shadow = @markerImageTargetShadow
          @markers[site.id] = new google.maps.Marker markerOptions
          @markers[site.id].siteId = site.id

      # Determine which markers need to be removed from the map
      toRemove = []
      for siteId, marker of @markers
        toRemove.push siteId unless dataSiteIds[siteId]

      # And remove them
      for siteId in toRemove
        @deleteMarker siteId

    drawClustersInMap: (clusters = []) =>
      if @reuseCurrentClusters
        dataClusterIds = {}

        # Add clusters if they are not already on the map
        for cluster in clusters
          dataClusterIds[cluster.id] = cluster.id
          @createCluster(cluster) unless @clusters[cluster.id]

        # Determine which clusters need to be removed from the map
        toRemove = []
        for clusterId, cluster of @clusters
          toRemove.push clusterId unless dataClusterIds[clusterId]

        # And remove them
        @deleteCluster clusterId for clusterId in toRemove
      else
        toRemove = []
        for clusterId, cluster of @clusters
          toRemove.push clusterId

        @deleteCluster clusterId for clusterId in toRemove
        @createCluster(cluster) for cluster in clusters

      @reuseCurrentClusters = true

    setAllMarkersInactive: =>
      editingSiteId = @editingSite()?.id()?.toString()
      for siteId, marker of @markers
        @setMarkerIcon marker, (if editingSiteId == siteId then 'target' else 'inactive')

    setAllMarkersActive: =>
      selectedSiteId = @selectedSite()?.id()?.toString()
      for siteId, marker of @markers
        @setMarkerIcon marker, (if selectedSiteId == siteId then 'target' else 'active')

    setMarkerIcon: (marker, icon) =>
      switch icon
        when 'active'
          marker.setIcon null
          marker.setShadow null
        when 'inactive'
          marker.setIcon @markerImageInactive
          marker.setShadow @markerImageInactiveShadow
        when 'target'
          marker.setIcon @markerImageTarget
          marker.setShadow @markerImageTargetShadow

    setupMarkerListener: (site, marker) =>
      @markerListener = google.maps.event.addListener marker, 'position_changed', =>
        site.position(marker.getPosition())

    deleteMarker: (siteId) =>
      if siteId
        if @markers[siteId]
          @markers[siteId].setMap null
          delete @markers[siteId]
      else if @marker
        @marker.setMap null
        delete @marker
        @deleteMarkerListener

    deleteMarkerListener: =>
      if @markerListener
        google.maps.event.removeListener @markerListener
        delete @markerListener

    createCluster: (cluster) =>
      @clusters[cluster.id] = new Cluster @map, cluster

    deleteCluster: (id) =>
      @clusters[id].setMap null
      delete @clusters[id]

  $.get "/collections.json", {}, (collections) =>
    # Compute all collections lat/lng: the center of all collections
    sum_lat = 0
    sum_lng = 0
    count = 0
    for collection in collections when collection.lat && collection.lng
      sum_lat += parseFloat(collection.lat)
      sum_lng += parseFloat(collection.lng)
      count += 1

    if count == 0
      sum_lat = 10
      sum_lng = 90
    else
      sum_lat /= count
      sum_lng /= count

    ko.applyBindings new CollectionViewModel(collections, sum_lat, sum_lng)

    $('#collections-dummy').hide()
    $('#collections-main').show()
