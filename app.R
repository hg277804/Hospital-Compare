#load all the libraries...

library(shiny)
library(shinythemes)
library(shinydashboard)
library(shinyWidgets)
library(leaflet)
library(scales) 
library(ggplot2)
library(lattice) 
library(dplyr) 
library(DT)
library(RMySQL)
library(DBI)


header  <- dashboardHeader(title = "Best Performing New York Hospitals", titleWidth = 400)

sidebar <- dashboardSidebar(
              helpText("This application offers Medicare patients recommendations for hospitals
              based on reported rates for quality care, safety in care, and preventative care. These
              rates have been reported by hospitals in New York and made available through the 
              Statewide Planning and Research Cooperative System.
              Enter in the zip code where you desire medical services:    "),
              textInput("zip","Search by ZIP code"),
              submitButton("Submit", icon("refresh")))

body    <-  dashboardBody(
              fluidRow(
                 tabsetPanel(
                      tabPanel("Quality", background = "black", tableOutput("quality"), 
                               leafletOutput(outputId = "nymap_quality")),
                      tabPanel("Safety", background = "blue", tableOutput("safety") , 
                               leafletOutput(outputId = "nymap_safety")),
                      tabPanel("Preventative Care", background = "blue", tableOutput("preventative"),
                               leafletOutput(outputId = "nymap_prevent")),
                      tabPanel("Usage", background = "blue",
                              helpText("This chart displays the top 10 zip code searches for hospitals."),
                              plotOutput("barchart"))
                      ),
                 )
            )



# Define UI for application 
ui <- dashboardPage(skin = "blue", header, sidebar, body)

             
              
# Define server logic to pull hospital performance
server <- function(input, output, session) {

    # define the action of the submit button
    output$value <- renderPrint({input$zip})
    
   
    # Make the barchart to show the most frequent zip_code usage
    output$barchart <- renderPlot({
      
      # connect to the database and insert zip code and timestamp
      con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", user = "root", 
                       host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                       password = "xxxxx", port = 3306)
      
      dbGetQuery(con, paste0("INSERT INTO QUERY_LOG(zip_code) VALUES('",input$zip, "');"))
      
      dbDisconnect(con)
      
        # connect to the database and submit the query for zip-code usage counts for the barchart      
        con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", user = "root", 
                       host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                       password = "xxxxx", port = 3306)
        
        plot_data <- dbGetQuery(con, paste0("SELECT COUNT(zip_code) count, zip_code from QUERY_LOG
                                GROUP BY zip_code ORDER by count DESC LIMIT 10;"))
        dbDisconnect(con)
        plot_data$zip_code = as.character(plot_data$zip_code)
        
        # plot the counts of zips used in searches
        ggplot(plot_data, aes(x= zip_code, y=count)) +
        geom_bar(stat = "identity") + 
        labs(xlab = "Zip Code", ylab = "Count")
    })
    
    
    #Make a table that lists top 3 hospitals for quality ratings
    output$preventative <- renderTable({
      
         #connect to database to obtain data
         con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", user = "root", 
                          host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                          password = "xxxxxx", port = 3306)
    
         # submit the query and disconnect from the DB
         data_preventable <- dbGetQuery(con, paste0("SELECT Hospital_Name as Hospital, address as
            Address, city as City, hgi.zip_code as 'Zip Code'
            FROM hospital_general_information hgi, potentially_preventable_indicators ppi
            WHERE hgi.Facility_ID = ppi.Facility_ID and hgi.region = (
            SELECT region FROM ny_zip_regions
            WHERE  hgi.Hospital_Name NOT LIKE '%Child%'  
            and hgi.Hospital_Name NOT LIKE '%addiction%'
            and zip_code = '", input$zip, "')
            ORDER BY ppi.mean_rate ASC 
            LIMIT 3;"))
    
         dbDisconnect(con)
         as.data.frame(data_preventable)
         
    })
    
    # Make a table that lists the top 3 hospitals for safety ratings
    output$safety <- renderTable({
        #connect to AWS
        con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", user = "root", 
                         host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                         password = "xxxxxxx", port = 3306)
        
        # submit the query and disconnect from the DB
        data_saftey <- dbGetQuery(con, paste0("SELECT Hospital_Name as Hospital, address as
            Address, city as City, hgi.zip_code as 'Zip Code' 
            FROM hospital_general_information hgi, safety_indicators si, PSI_code_weights psi 
            WHERE hgi.Facility_ID = si.Facility_ID and si.PSI_Code = psi.PSI_Code and hgi.region = (
            SELECT region FROM ny_zip_regions
            WHERE  hgi.Hospital_Name NOT LIKE '%Child%'
            and hgi.Hospital_Name NOT LIKE '%addiction%'
            and zip_code = '", input$zip, "')
            GROUP BY si.Facility_ID    
            ORDER BY avg(si.Observe_Rate*psi.weight) ASC 
            LIMIT 3;"))
        
        dbDisconnect(con)
        as.data.frame(data_saftey)
        
    }) 
    
    
    # Make a table that lists the top 3 hopsitals for quality care
    output$quality <- renderTable({
        #connect to AWS
        con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", user = "root", 
                         host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                         password = "xxxxxxx", port = 3306)
        
        # submit the query and disconnect from the DB
        data_quality <- dbGetQuery(con, paste0("SELECT Hospital_Name as Hospital, address as
            Address, city as City, hgi.zip_code as 'Zip Code' 
                      FROM hospital_general_information hgi, quality_indicators qi, IQI_code_weights iqi 
                      WHERE hgi.Facility_ID = qi.Facility_ID and qi.IQI_Code = iqi.IQI_code and hgi.region = (
	                    SELECT region FROM ny_zip_regions
	                    WHERE  hgi.Hospital_Name NOT LIKE '%Child%' 
	                    and hgi.Hospital_Name NOT LIKE '%addiction%'
	                    and zip_code = '", input$zip, "')
                      GROUP BY qi.Facility_ID
                      ORDER BY avg(qi.Observed_Rate * iqi.weight) ASC LIMIT 3;"))
        
        dbDisconnect(con)
        as.data.frame(data_quality)
        
    }) 

    # get data to display hospitals that rank best in safety
    data_safety <- reactive({ con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", 
                   user = "root", host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                   password = "xxxxxx", port = 3306)

        # submit the query and disconnect from the DB
        data <- dbGetQuery(con, paste0("SELECT latitude, longitude, hl.hospital_name
                From hospital_general_information hgi, safety_indicators si, PSI_code_weights psi, hospital_location hl
                where hgi.Facility_ID = si.Facility_ID and si.PSI_Code = psi.PSI_Code and 
                hl.hospital_name = hgi.hospital_name
                and hgi.region = (
                SELECT region FROM ny_zip_regions
                WHERE  hl.Hospital_Name NOT LIKE '%Child%' 
                and hgi.Hospital_Name NOT LIKE '%addiction%'
                and zip_code = '", input$zip, "')
                GROUP BY si.Facility_ID    
                ORDER BY avg(si.Observe_Rate * psi.weight) ASC 
                LIMIT 3;"))
        
        dbDisconnect(con)
        as.data.frame(data)  
        })
    
    # get data to display hospitals that rank best in quality
    data_quality <- reactive({ con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", 
                    user = "root", host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                    password = "xxxxx", port = 3306)
        
        # submit the query and disconnect from the DB
        data <- dbGetQuery(con, paste0("SELECT latitude, longitude, hl.hospital_name 
                FROM hospital_general_information hgi, quality_indicators qi, IQI_code_weights iqi, hospital_location hl 
                WHERE hgi.Facility_ID = qi.Facility_ID and qi.IQI_Code = iqi.IQI_Code and 
                hl.hospital_name = hgi.hospital_name and hgi.region = (
                SELECT region FROM ny_zip_regions
                WHERE  hl.Hospital_Name NOT LIKE '%Child%' 
                and hgi.Hospital_Name NOT LIKE '%addiction%'
                and zip_code = '", input$zip, "')
                GROUP BY qi.Facility_ID    
                ORDER BY avg(Observed_Rate*weight) ASC 
                LIMIT 3;"))
        
        dbDisconnect(con)
        as.data.frame(data)   
        })
    
    data_prevent <- reactive({con <- dbConnect(drv = RMySQL::MySQL(), dbname = "medicare", 
                         user = "root", host = 'medicare.chonyz354djh.us-east-2.rds.amazonaws.com',
                         password = "xxxxxxx", port = 3306)
    
    # submit the query and disconnect from the DB
        data <- dbGetQuery(con, paste0("SELECT latitude, longitude, hl.hospital_name 
                FROM hospital_general_information hgi, potentially_preventable_indicators ppi, hospital_location hl
                WHERE hgi.Facility_ID = ppi.Facility_ID and 
                hl.hospital_name = hgi.hospital_name and hgi.region = (
                SELECT region FROM ny_zip_regions
                WHERE hl.Hospital_Name NOT LIKE '%Child%' 
                and hgi.Hospital_Name NOT LIKE '%addiction%'
                and zip_code = '", input$zip, "')
                ORDER BY ppi.mean_rate ASC 
                LIMIT 3;"))
        
        dbDisconnect(con)
        as.data.frame(data)
        })
    
    # make the map for best hospitals in safety    
    output$nymap_safety <- renderLeaflet({
        
        map_data = data_safety() # call the map's data
        map_data$hospital_name = toupper(map_data$hospital_name)
        
        # Zoom the map to the markers for the hospitals
        AvLat = mean( map_data$latitude, na.rm = TRUE )
        AvLon = mean( map_data$longitude, na.rm = TRUE )
        zm <- 9
        
        if ( is.na(AvLat) || is.na(AvLon) ) { 
            AvLon <-  -74.2179
            AvLat <-  43.2994
            zm <- 6 
        } 
        
        # Create the hyperlink for the markers in the map
        name <- gsub(" ","+", map_data$hospital_name)
        pop_data <- paste0("<b><a href='https://www.google.com/search?q=",name,
                           "'>", map_data$hospital_name, "</a></b>")
    
        # focus map over New York State
        leaflet() %>%
            setView(lng =AvLon, lat = AvLat, zoom = zm) %>%
            addTiles() %>% 
            addMarkers(
                lng = map_data$longitude, lat = map_data$latitude, 
                popup = pop_data)  }) 
    
    # make the map for hospitals with best quality care
    output$nymap_quality <- renderLeaflet({
      
      map_data = data_quality() # call the map's data
      map_data$hospital_name = toupper(map_data$hospital_name)
      
      # Zoom the map to the markers for the hospitals 
      AvLat = mean( map_data$latitude, na.rm = TRUE )
      AvLon = mean( map_data$longitude, na.rm = TRUE )
      zm <- 9
      
      if ( is.na(AvLat) || is.na(AvLon) ) { 
        AvLon <-  -74.2179
        AvLat <-  43.2994
        zm <- 6 
      }  
      
      # Create the hyperlink for the markers in the map
      name <- gsub(" ","+", map_data$hospital_name)
      pop_data <- paste0("<b><a href='https://www.google.com/search?q=",name,
                         "'>", map_data$hospital_name, "</a></b>")
                    

      
      # focus map over New York State
      leaflet() %>%
        setView(lng =AvLon, lat = AvLat, zoom = zm) %>%
        addTiles() %>% 
        addMarkers(
          lng = map_data$longitude, lat = map_data$latitude, 
          popup = pop_data) 
      })
 
    # make the map for hospitals with best preventative care
    output$nymap_prevent <- renderLeaflet({
      
      map_data = data_prevent()
      map_data$hospital_name = toupper(map_data$hospital_name)
      
      AvLat = mean( map_data$latitude, na.rm = TRUE )
      AvLon = mean( map_data$longitude, na.rm = TRUE )
      zm <- 9
      
      
      if ( is.na(AvLat) || is.na(AvLon) ) { 
        AvLon <-  -74.2179
        AvLat <-  43.2994
        zm <- 6 
      } 
      
      # Create the hyperlink for the markers in the map
      name <- gsub(" ","+", map_data$hospital_name)
      pop_data <- paste0("<b><a href='https://www.google.com/search?q=",name,
                         "'>", map_data$hospital_name, "</a></b>")
      
      # focus map over New York State
      leaflet() %>%
        setView(lng =AvLon, lat = AvLat, zoom = zm) %>%
        addTiles() %>% 
        addMarkers(
          lng = map_data$longitude, lat = map_data$latitude, 
          popup = pop_data)
      })   
   
}

# Run the application 
shinyApp(ui = ui, server = server)

