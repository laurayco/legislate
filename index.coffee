cheerio = require "cheerio"
Constants = require "./constants.coffee"
request = require "request"
xpath = require "xpath"
xmldom = (require "xmldom").DOMParser
sugar = require "sugar"
sugar.extend()

class Scanner
  constructor: (@page,@since=null) ->
    if @since instanceof Number
      @since = new Date(@since)
  filter_relevant: (pages) ->
    pages.filter (p)=>
      p["href"].endsWith(".xml") and (p["modified"].isAfter(@since) or @since is null)
  run: (cb)-> request @page, @build_process cb
  build_process: (cb)->
    return (err,response,data)=>cb @filter_relevant @process err,response,data
  process: (err, response, data) =>
    if err
      console.log err
      return
    $ = cheerio.load data
    $("#bulkdata table tr").map (i,e)->
      href = cheerio("td:first-child a", e)
      if href.length
        href = href.first().attr("href")
        date = cheerio "td:nth-child(2)",e
          .filter (i,del) ->
            cheerio(del).text().trim().length
        if date.length
          date = Date.create date.first().text(), Constants.date_options
          return {
            href: href
            modified: date
          }
        else return null
      else return null
    .get()
    .filter (x)->x!=null
  get_host: -> @page.slice @page.indexOf("/")

class Selector
  constructor: (@doc)->
  select: (query)-> xpath.select query, @doc
  get_text: (query)-> (@select query).toString()

class PageProcessor
  constructor: (page)->
    @scanner = new Scanner page, @get_last_date page
  get_last_date: ->
    return Date.create "2/25/2017"
  process_doc: (doc)->
    selector = new Selector(doc)
    r = {
      title: selector.get_text "//bill/title/text()"
      bill_number: selector.get_text "//bill/billNumber/text()"
      bill_type: selector.get_text "//bill/billType/text()"
      modified: Date.create selector.get_text "//bill/updateDate"
      created: Date.create selector.get_text "//bill/createDate"
      introduced: Date.create selector.get_text "//bill/introducedDate"
    }
    subjects = selector.select "//bill/subjects/billSubjects/legislativeSubjects/item/name/text()"
    r.subjects = subjects.map (x)->x.toString()
    subjects = selector.select "//bill/subjects/billSubjects/policyArea/name/text()"
    r.subjects = r.subjects.union subjects.map (x)->x.toString()
    r.summaries = (selector.select "//bill/summaries/billSummaries/item").map (summary_object)->
      selector = new Selector(summary_object)
      {
        version: selector.get_text "versionCode"
        text: (selector.select "text")[0].firstChild.data
        updated: selector.get_text "updateDate"
        introduced: selector.get_text "actionDate"
        last_summary_update: selector.get_text "lastSummaryUpdate"
      }
    return r
  run: ->
    @scanner.run (results)=>
      todo = results.map (x)=>@scanner.page + "/" + x["href"]
      failed = []
      finished = []
      attempts = {}
      attempts[href] = 0 for href in todo
      while todo.length
        for href in todo
          request href, (err,response,data)=>
            attempts[href] = attempts[href] + 1
            if err
              console.log "Failed #{href}"
              failed.push href
            else
              console.log "Retrieved #{href}"
              doc = @process_doc (new xmldom()).parseFromString(data)
              @store_doc href, doc
        todo = failed.filter (x)->attempts[x] < Constants.max_attempts
        failed = []
  store_doc: (href,doc)->
    console.log "#{doc.bill_type}#{doc.bill_number}: #{doc.title}"
    console.log "#" + doc.subjects.map((x)->x.camelize()).join(" #")

p = new PageProcessor "https://www.gpo.gov/fdsys/bulkdata/BILLSTATUS/115/hres"
p.run()
