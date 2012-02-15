@initLayers = ->
  class Layer
    constructor: (data) ->
      @id = ko.observable data?.id
      @name = ko.observable data?.name
      @public = ko.observable data?.public
      if data?.fields
        @fields = ko.observableArray($.map(data.fields, (x) -> new Field(x)))
      else
        @fields = ko.observableArray([])
      @hasFocus = ko.observable(false)
      @valid = ko.computed => @hasName() && @fieldsAreValid()

    hasName: => $.trim(@name()).length > 0

    fieldsAreValid: =>
      return false if @fields().length == 0

      codes = []
      names = []

      # Check that the name and code are not duplicated
      for field in @fields()
        return false unless field.valid()
        return false if names.indexOf(field.name()) >= 0
        return false if codes.indexOf(field.code()) >= 0
        names.push field.name()
        codes.push field.code()

      # Now check that the names and codes don't apper in other layers
      if window.model
        for layer in window.model.layers() when layer != @
          for field in layer.fields()
            return false if names.indexOf(field.name()) >= 0
            return false if codes.indexOf(field.code()) >= 0

      true

    toJSON: =>
      id: @id()
      name: @name()
      public: @public()
      fields_attributes: $.map(@fields(), (x) -> x.toJSON())

  class Field
    constructor: (data) ->
      @id = ko.observable data?.id
      @name = ko.observable data?.name
      @code = ko.observable data?.code
      @kind = ko.observable data?.kind
      @options = if data.config?
                   ko.observableArray($.map(data.config, (x) -> new Option(x)))
                 else
                   ko.observableArray()
      @hasFocus = ko.observable(false)
      @isOptionsKind = ko.computed => @kind() == 'selectOne' || @kind() == 'selectMany'
      @valid = ko.computed => @hasName() && @hasCode() && (!@isOptionsKind() || @options().length > 1)

    hasName: => $.trim(@name()).length > 0

    hasCode: => $.trim(@code()).length > 0

    buttonClass: =>
      switch @kind()
        when 'text' then 'ltext'
        when 'numeric' then 'lnumber'
        when 'selectOne' then 'lsingleoption'
        when 'selectMany' then 'lmultipleoptions'

    toJSON: =>
      json =
        name: @name()
        code: @code()
        kind: @kind()
      json.config = $.map(@options(), (x) -> x.name()) if @isOptionsKind()
      json

  class Option
    constructor: (name) ->
      @name = ko.observable(name)

  class LayersViewModel
    constructor: (collectionId, layers) ->
      @collectionId = collectionId
      @layers = ko.observableArray $.map(layers, (x) -> new Layer(x))
      @currentLayer = ko.observable()
      @currentField = ko.observable()
      @newOption = ko.observable('')
      @optionValid = ko.computed => $.trim(@newOption()).length > 0

    newLayer: =>
      layer = new Layer
      @layers.push(layer)
      @currentLayer(layer)
      layer.hasFocus(true)

    editLayer: (layer) =>
      @originalFields = $.map(layer.fields(), (x) -> x)
      @currentLayer(layer)
      @currentField(layer.fields()[0]) if layer.fields().length > 0
      layer.hasFocus(true)

    cancelLayer: =>
      if @currentLayer().id()
        @currentLayer().fields.removeAll()
        @currentLayer().fields.push(field) for field in @originalFields
      else
        @layers.remove(@currentLayer()) unless @currentLayer().id()
      @currentLayer(null)
      @currentField(null)

    saveLayer: =>
      callback = (data) =>
        @currentLayer().id(data.id)
        @currentLayer(null)

      json = {layer: @currentLayer().toJSON()}

      if @currentLayer().id()
        json._method = 'put'
        $.post "/collections/#{@collectionId}/layers/#{@currentLayer().id()}.json", json, callback
      else
        $.post "/collections/#{@collectionId}/layers.json", json, callback

    deleteLayer: (layer) =>
      if confirm("Are you sure you want to delete layer #{layer.name()}?")
        $.post "/collections/#{@collectionId}/layers/#{layer.id()}", {_method: 'delete'}, =>
          @layers.remove(layer)

    newTextField: => @newField 'text'
    newNumericField: => @newField 'numeric'
    newSelectOneField: => @newField 'selectOne'
    newSelectManyField: => @newField 'selectMany'

    newField: (kind) =>
      @currentField(new Field(kind: kind))
      @currentLayer().fields.push(@currentField())
      @currentField().hasFocus(true)

    selectField: (field) =>
      @currentField(field)
      @currentField().hasFocus(true)

    deleteField: (field) =>
      @currentLayer().fields.remove(field)
      if @currentField() == field
        if @currentLayer().fields().length == 0
          @currentField(null)
        else
          @currentField(@currentLayer().fields()[0])
          @currentField().hasFocus(true)

    newOptionKeyPress: (field, event) =>
      switch event.keyCode
        when 13 then @addOption()
        else true

    optionBlur: (option) =>
      if $.trim(option.name()).length == 0
        @removeOption(option)

    addOption: =>
      return unless @optionValid()
      @currentField().options.push(new Option(@newOption()))
      @newOption('')

    removeOption: (option) =>
      @currentField().options.remove(option)

  match = window.location.toString().match(/\/collections\/(\d+)\/layers/)
  collectionId = parseInt(match[1])

  $.get "/collections/#{collectionId}/layers.json", {}, (layers) =>
    window.model = new LayersViewModel(collectionId, layers)
    ko.applyBindings window.model
