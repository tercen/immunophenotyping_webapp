

import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:immunophenotyping_template_assistant/ui_utils.dart';
import 'package:immunophenotyping_template_assistant/util.dart';
import 'package:list_picker/list_picker.dart';
import 'package:web/web.dart' as web;
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_model/sci_model_base.dart' as model;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:tson/tson.dart' as tson;
import 'package:immunophenotyping_template_assistant/data.dart';

class AnnotationScreen extends StatefulWidget {
  final AppData appData;
  const AnnotationScreen({super.key,  required this.appData});

  @override
  State<AnnotationScreen> createState()=> _AnnotationScreenState();

}


class AnnotationDataSource extends DataTableSource{
  sci.Table tbl;
  List<TextEditingController> controllerList = [];
  List<int> changedRows = [];
  AnnotationDataSource(this.tbl );

  @override
  DataRow? getRow(int index) {
    var ctrl = TextEditingController(text: tbl.columns[1].values[index]);
    

    if( controllerList.length <= index ){
      controllerList.add(ctrl);
    }

    return DataRow(
          cells: <DataCell>[
            DataCell(Text(tbl.columns[0].values[index])),
            DataCell(
              TextField(
                onChanged: (txt) {
                  if( !changedRows.contains(index) ){
                    changedRows.add(index);
                  }
                },
                controller: ctrl,
                decoration: 
                  const InputDecoration(
                    border: UnderlineInputBorder()
                  )
                
              )
            ),
          ],
        );
  }
  
  @override
  bool get isRowCountApproximate => false;
  
  @override
  int get rowCount => tbl.nRows;
  
  @override
  int get selectedRowCount => 0;
}

class _AnnotationScreenState extends State<AnnotationScreen>{
  // late Map<String, Object> dataHandler;
  final factory = tercen.ServiceFactory();
  late sci.Schema annotSch;
  
  Future<sci.Table> _readTable() async {
    annotSch = await factory.tableSchemaService.get(widget.appData.channelAnnotationDoc.id);
    var channelAnnotationTbl = await factory.tableSchemaService.select(annotSch.id, ["channel_name", "channel_description"], 0, annotSch.nRows);

    return channelAnnotationTbl;
  }
  @override
  Widget build(BuildContext context) {
    

    return FutureBuilder(
      future: _readTable(), 
      builder: (context, snapshot ){
        
        if( snapshot.hasData ){
          
          AnnotationDataSource dataSource = AnnotationDataSource(snapshot.requireData);
          return Column(
                    children: [
                      Theme(data: Theme.of(context).copyWith(
                              cardColor: const Color.fromARGB(255, 252, 252, 252),
                              dividerColor: const Color.fromARGB(255, 188, 183, 255),
                            ), 
                            child: 
                                PaginatedDataTable(

                                columns: const <DataColumn>[
                                  DataColumn(
                                    label: Text('Name'),
                                  ),
                                  DataColumn(
                                    label: Text('Description'),
                                  ),
                                  
                                ],
                                source: dataSource,
                      
                        )
                      ),

                      addSeparator(),

                      addAlignedWidget(
                        ElevatedButton(
                          style: setButtonStyle("enabled"),
                          onPressed: (){
                            // sci.ProjectDocument chanAnnotDoc =  widget.appData.channelAnnotationDoc;
                            sci.Table tbl = snapshot.requireData;
                            
                            if(dataSource.changedRows.isNotEmpty){
                              print("Creating new column...");
                              // sci.Column newCol = sci.Column();
                              // newCol.values = List.from(tbl.columns[1].values);
                              // newCol.name = tbl.columns[1].name;
                              // newCol.id = tbl.columns[1].id;
                              // newCol.nRows = tbl.columns[1].nRows;
                              // newCol.type = tbl.columns[1].type;
                              // newCol.size = -1;
                              List<String> newAnnotations = List.from(tbl.columns[1].values);
                              for(int idx in dataSource.changedRows ){

                                newAnnotations[idx] = dataSource.controllerList[idx].text;

                              }

                              var annotationTable = sci.Table()
                                  ..properties.name = widget.appData.channelAnnotationDoc.name;
                              
                              annotationTable.columns
                                ..add(sci.Column()
                                  ..type = 'string'
                                  ..name = tbl.columns[0].name
                                  ..values =
                                      tson.CStringList.fromList(List.from(tbl.columns[0].values)))
                                ..add(sci.Column()
                                  ..type = 'string'
                                  ..name = tbl.columns[1].name
                                  ..values = tson.CStringList.fromList(newAnnotations));

                              print("Setting new column");
                              
                              print(annotationTable.toJson());

                              print("Uploading new table");
                              uploadTable(annotationTable, 
                                        annotationTable.properties.name, 
                                        widget.appData.channelAnnotationDoc.projectId, 
                                        widget.appData.channelAnnotationDoc.acl.owner
                                        widget.appData.channelAnnotationDoc.folderId
                              );
                              print("Deleting old table");
                              factory.projectDocumentService.delete(widget.appData.channelAnnotationDoc.id, widget.appData.channelAnnotationDoc.rev);
                              
                              // factory.tableSchemaService.update(tbl.)
                              
                            }
                            
                          }, 
                          child: const Text("Update Descriptions")
                        )
                      )
                      
                    ],
                  );
              
        }else{
          // TODO better place the loading icon
          return const Center(
                    child: CircularProgressIndicator(),
                  );
        }
      }
    );

    
  
    
  }
}