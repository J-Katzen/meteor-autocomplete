class @AutoComplete

  @KEYS: [
    40, # DOWN
    38, # UP
    13, # ENTER
    27, # ESCAPE
    9   # TAB
  ]

  constructor: (settings) ->
    @limit = settings.limit || 5
    @position = settings.position || "bottom"

    @rules = settings.rules
    # Expressions compiled for range from last word break to current cursor position
    @expressions = (new RegExp('(^|\\b|\\s)' + rule.token + '([\\w.]*)$') for rule in @rules)

    # Reactive dependencies for current matching rule and filter
    @ruleDep = new Deps.Dependency
    @filterDep = new Deps.Dependency
    Session.set("-autocomplete-id", ""); # Use this for Session.equals()

  onKeyUp: (e) ->
    startpos = @$element.getCursorPosition()
    val = @getText().substring(0, startpos)

    ###
      Matching on multiple expressions.
      We always go from an matched state to an unmatched one
      before going to a different matched one.
    ###
    i = 0
    breakLoop = false
    while i < @expressions.length
      matches = val.match(@expression[i])

      # matching -> not matching
      if not matches and @matched is i
        @matched = -1
        @ruleDep.changed()
        breakLoop = true

      # not matching -> matching
      if matches and @matched is -1
        @matched = i
        @ruleDep.changed()
        breakLoop = true

      # Did filter change?
      if matches and @filter isnt matches[2]
        @filter = matches[2]
        @filterDep.changed()
        breakLoop = true

      break if breakLoop

  onKeyDown: (e) ->
    return if @matched is -1 or (@KEYS.indexOf(e.keyCode) < 0)

    switch e.keyCode
      when 9, 13 # TAB, ENTER
        @select()
      when 40
        @next()
      when 38
        @prev()
      when 27 # ESCAPE; not sure what function this should serve, cause it's vacuous in jquery-sew
        @hideList()

    e.preventDefault()

  onFocus: @onKeyUp

  onBlur: @hideList

  onItemClick: (doc, e) ->
    @replace doc[@rules[@matched].field]
    @hideList()

  onItemHover: (index, e) ->
    @index = index
    @hightlightItem()

  # Replace text with currently selected item
  select: ->
    docId = Deps.nonreactive Session.get("-autocomplete-id")
    rule = @rules[@matched]
    @replace rule.collection.findOne(docId)[rule.field]
    @hideList()

  # Select next item in list
  next: ->
    next = $(@tmplInst.find("-autocomplete-item selected")).next()
    if next.length
      nextId = Spark.getDataContext(next[0])._id
    else
      # Go back to first first item
      nextId = Spark.getDataContext(@tmplInst.find("-autocomplete-item"))._id
    Session.set("-autocomplete-id", nextId)

  # Select previous item in list
  prev: ->
    prev = $(@tmplInst.find("-autocomplete-item selected")).prev()
    if prev.length
      prevId = Spark.getDataContext(prev[0])._id
    else
      # Go to end of list
      last = $(@tmplInst.find("-autocomplete-container")).find(":last-child")
      prevId = Spark.getDataContext(last[0])._id
    Session.set("-autocomplete-id", prevId)

  # Replace the appropriate region
  replace: (replacement) ->
    startpos = @$element.getCursorPosition()
    fullStuff = @getText()
    val = fullStuff.substring(0, startpos)
    val = val.replace(@expressions[@matched], "$1" + @rules[@matched].token + replacement)
    posfix = fullStuff.substring(startpos, fullStuff.length)
    separator = (if posfix.match(/^\s/) then "" else " ")
    finalFight = val + separator + posfix
    @setText finalFight
    @$element.setCursorPosition val.length + 1

  hideList: ->
    @matched = -1
    @ruleDep.changed()

  getText: ->
    return @$element.val() || @$element.text()

  setText: (text) ->
    if @$element.is("input,textarea")
      @$element.val(text)
    else
      @$element.html(text)

  ###
    Reactive/rendering functions
  ###
  listShown: ->
    @ruleDep.depend()
    return @matched >= 0

  filteredList: ->
    # @ruleDep.depend() # optional as long as we use filterDep, cause list will always get re-rendered
    @filterDep.depend()
    return null if @matched is -1

    rule = @rules[@matched]

    args = {}
    args[rule.field] =
      $regex: @filter # MIND BLOWN!
      $options: "i"

    return rule.collection.find(args, {limit: @limit})

  # This doesn't need to be reactive because list already changes reactively
  # and will cause all of the items to re-render anyway
  currentTemplate: -> @rules[@matched].template

