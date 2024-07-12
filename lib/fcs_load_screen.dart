

import 'dart:async';
import 'dart:io';


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:list_picker/list_picker.dart';
import 'package:sn_progress_dialog/sn_progress_dialog.dart';
import 'package:web/web.dart' as web;
import 'package:sci_tercen_client/sci_client.dart' as sci;
import 'package:sci_tercen_client/sci_client_service_factory.dart' as tercen;
import 'package:tson/tson.dart' as tson;
import 'package:uuid/uuid.dart';

class FcsLoadScreen extends StatefulWidget {
  const FcsLoadScreen({super.key});

  @override
  State<FcsLoadScreen> createState()=> _FcsLoadScreenState();

}


//TODO Improve general screen layout
//TODO Fix progress message

class _FcsLoadScreenState extends State<FcsLoadScreen>{
  late ProgressDialog progressDialog = ProgressDialog(context: context);
  bool finishedUploading = false;
  int total = -1;
  int processed = -1;
  late StreamSubscription<sci.TaskEvent> sub;

  String progress = "";
  final factory = tercen.ServiceFactory();
  late DropzoneViewController dvController;
  late FilePickerResult result;
  String selectedTeam = "Please select a team";
  Color dvBackground = Colors.white;
  List<String> filesToUpload = ["Drag Files Here"];
  List<web.File> htmlFileList = [];
  var workflowTfController = TextEditingController(text: "Immunophenotyping Workflow");

  final List<String> teamNameList = [];
  sci.Project project = sci.Project();

  @override
  void initState () {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_){
      _loadTeams();
      // _debugInfo();
      
    });

    // http://127.0.0.1:5400/lib/w/5e8e784622396f3064cd7cd90e7376e7/ds/b3718281-eb72-47a1-b962-003c49b9e539
    
  }

  Future<void> _debugInfo() async {
    sci.Workflow wkf = await factory.workflowService.get("5e8e784622396f3064cd7cd90e7376e7");
    for( var stp in wkf.steps){
      print(stp.toJson());
    }
  }
  Future<void> _loadTeams() async {
    var token = Uri.base.queryParameters["token"] ?? '';
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);

    List<sci.Team> teamList = await factory.teamService.findTeamByOwner(keys: [decodedToken["data"]["u"]]);

      for( var team in teamList){
      teamNameList.add(team.name);
    }

  }


  List<Widget> _buildFileList(){
    List<Widget> wdgList = [];
    for(int i = 0; i < filesToUpload.length; i++){
      if( filesToUpload[i] != "Drag Files Here"){
        Row entry = Row(
          children: [
            const Icon(Icons.delete_rounded),
            Text(filesToUpload[i], style: const TextStyle(fontSize: 14, color: Colors.black45))
          ],
        );           
        wdgList.add(entry);
      }else{
        wdgList.add(Text(filesToUpload[i], style: const TextStyle(fontSize: 14, color: Colors.black45)));
      }
    }

    return wdgList;
  }

  void _updateFilesToUpload(web.File wf){
    if( filesToUpload[0] == "Drag Files Here"){
      filesToUpload.removeAt(0);
    }
    filesToUpload.add(wf.name);

    htmlFileList.add(wf);
  }


  void _uploadFiles() async {
    var uuid = const Uuid();


    // Create a project to store the workflow
    if( project.id == "" ){
      project.name = workflowTfController.text;
      project.acl.owner = selectedTeam;
      project = await factory.projectService.create(project);
    }

    List<sci.FileDocument> uploadedDocs = [];

    for( web.File file in htmlFileList ){
      var bytes = await dvController.getFileData(file);
      sci.FileDocument docToUpload = sci.FileDocument()
              ..name = file.name
              ..projectId = project.id
              ..acl.owner = selectedTeam;
      
      
      uploadedDocs.add( await factory.fileService.upload(docToUpload, Stream.fromIterable([bytes]) ) );
    }
    
    // Reading FCS
    // 1. Get operator
    var installedOperators = await factory.documentService.findOperatorByOwnerLastModifiedDate(startKey: selectedTeam, endKey: '');
    sci.Document op = sci.Document();
    for( var o in installedOperators ){
      if( o.name == "FCS"){
        op = o;
      }
    }


    // 2. Prepare the computation task
    sci.CubeQuery query = sci.CubeQuery();
    query.operatorSettings.operatorRef.operatorId = op.id;
    query.operatorSettings.operatorRef.operatorKind = op.kind;
    query.operatorSettings.operatorRef.name = op.name;

    // Query Projection
    sci.Factor docFactor = sci.Factor()
            ..name = "documentId"
            ..type = "string";

    query.colColumns.add(docFactor);


    // Data to feed projection
    sci.Table tbl = sci.Table();

    sci.Column col = sci.Column()
          ..name = "documentId"
          ..type = "string"
          ..id = "documentId"
          ..nRows = 1
          ..size = -1
          ..values = tson.CStringList.fromList([uuid.v4()]);
    
    tbl.columns.add(col);

    col = sci.Column()
          ..name = ".documentId"
          ..type = "string"
          ..id = ".documentId"
          ..nRows = 1
          ..size = -1
          ..values = tson.CStringList.fromList([uploadedDocs[0].id]);
    
    tbl.columns.add(col);

    var id = uuid.v4();
    sci.InMemoryRelation rel = sci.InMemoryRelation()
            ..id = id
            ..inMemoryTable = tbl;

    query.relation = rel;
    query.axisQueries.add(sci.CubeAxisQuery());
    

    sci.RunComputationTask compTask = sci.RunComputationTask()
          ..state = sci.InitState()
          ..owner = selectedTeam
          ..query = query
          ..projectId = project.id;
    
    

    compTask = await factory.taskService.create(compTask) as sci.RunComputationTask;


    var taskStream = factory.eventService.listenTaskChannel(compTask.id, true).asBroadcastStream();
    
    //{kind: TaskProgressEvent, id: , isDeleted: false, rev: ,
    // date: {kind: Date, value: 2024-07-11T16:29:54.226033Z}, taskId: 3adc6ed4b2e0e95f81fa2488033fb5f9, message: measurement, total: 8, actual: 2}
    var currentFile = "";


    sub = taskStream.listen((evt){
      var evtMap = evt.toJson();
      if(evtMap["kind"] == "TaskProgressEvent"){
        // setState(() {
        //   print(evtMap);
        //   if( currentFile != uploadedDocs[0].name){
        //     currentFile = uploadedDocs[0].name;
        //     if(progressDialog.isOpen()){
        //       progressDialog.close();
        //     }
            
        //     progressDialog.show(
        //           completed: null,
        //           msg: "Processing file ${uploadedDocs[0].name}", 
        //           max: evtMap["total"] as int,
        //           barrierColor: const Color.fromARGB(125, 0, 0, 0));
        //   }
        //   progressDialog.update(value: evtMap["actual"] as int);
        // });
      }
    });


      
// try {
//   await for (var evt in stream) {
//     state.taskState = evt.state;
//   }
// } catch (e) {
//   state
//     ..taskId = ''
//     ..taskState = FailedState.fromError(e);

//   (state.taskState as FailedState).throwError();

//   return;
// }
      

    sub.onDone((){
      _getComputedRelation(compTask.id);
      
      finishedUploading = true;
    });

  }

  void _tryToPrint(String id, String name) async {
    try {
      print("Trying to print $name");
      sci.Schema sch = await factory.tableSchemaService.get(id);
      print(sch.toJson());
    } catch (e) {
      print("$name failed");
    }
  }

  void _getComputedRelation(String taskId) async{
    var compTask = await factory.taskService.get(taskId) as sci.RunComputationTask;
    // sci.CompositeRelation rel = compTask.computedRelation as sci.CompositeRelation;
    // print(rel.toJson());
    // sci.CompositeRelation cr = rel.joinOperators[0].rightRelation as sci.CompositeRelation;
    // sci.Schema sch = await factory.tableSchemaService.get(cr.joinOperators[0].rightRelation.id);
    // print(sch.toJson());

// projectFiles = context.context.client.projectDocumentService.findProjectObjectsByFolderAndName(\
    // [projectId,  "ufff0", "ufff0"],\
    // [projectId, "",""], useFactory=False, limit=25000 )

    List<sci.ProjectDocument> projObjs = await factory.projectDocumentService.findProjectObjectsByFolderAndName(startKey: [project.id, "ufff0", "ufff0"], endKey: [project.id, "", ""]);

    for( var po in projObjs ){
      //TODO Need to check for && po.name.contains(uploadedFiledoc name ...)
      if(po.name.contains( "Channel-Descriptions" )  ){
        // print(po.toJson());
        sci.Schema sch = await factory.tableSchemaService.get(po.id);
        sci.Table res = await factory.tableSchemaService.select(sch.id, ["channel_name", "channel_description"], 0, sch.nRows);
        print(res.toJson());
        // {kind: TableSchema, id: 3adc6ed4b2e0e95f81fa248803fd0355, isDeleted: false, rev: 2-b74f46061e29684a6df30d16e07bb31d, description: , name: Channel-Descriptions-fcs_test.zip-07_11_24-19_45_36, acl: {kind: Acl, owner: lib, aces: []}, createdDate: {kind: Date, value: 2024-07-11T19:45:36.848084Z}, lastModifiedDate: {kind: Date, value: 2024-07-11T19:45:36.848084Z}, urls: [], tags: [], meta: [], url: {kind: Url, uri: }, version: , isPublic: false, projectId: 3adc6ed4b2e0e95f81fa248803fc97c4, folderId: 3adc6ed4b2e0e95f81fa248803fcd03c, nRows: 69, columns: [{kind: ColumnSchema, id: 75502a28-3967-4987-a7f1-97df20e9ffb1, name: channel_name, type: string, nRows: 0, size: -1, metaData: {kind: ColumnSchemaMetaData, sort: [], ascending: true, quartiles: [], properties: []}}, {kind: ColumnSchema, id: 6b65f454-835a-4c9b-9232-b36ff9c0f054, name: channel_description, type: string, nRows: 0, size: -1, metaData: {kind: ColumnSchemaMetaData, sort: [], ascending: true, quartiles: [], properties: []}}, {kind: ColumnSchema, id: 814a47e2-5ec9-447c-9e81-133f22f8017e, name: channel_id, type: int32, nRows: 0, size: -1, metaData: {kind: ColumnSchemaMetaData, sort: [], ascending: true, quartiles: [], properties: []}}], dataDirectory: default/50/7b/7b509af5bc354ef4af9d6b7def4072eb, relation: {kind: Relation, id: 4e5d0925-59cf-4fb3-95b2-df216641f054}}
      }
    }
    // print("Selecting");
    // sci.Table tbl = await factory.tableSchemaService.select(sch.id, ["filename", ".content"], 0, 1);
    // print(tbl.toJson());
    // _tryToPrint(rel.mainRelation.id, "rel.mainRelation.id");
    // 
    // _tryToPrint(cr.joinOperators[0].rightRelation.id, "rel.joinOperators[0]...rightRelation.id"); 
    // _tryToPrint(rel.joinOperators[1].rightRelation.id, "rel.joinOperators[1].rightRelation.id"); // Summary
    
  }

  
  void  _processSingleFileDrop(ev){
    if (ev is web.File) {
      setState(() {
        _updateFilesToUpload(ev);
      });
      // final bytes = await controller1.getFileData(ev);
      // print(bytes.sublist(0, min(bytes.length, 20)));
    } 
  }

  Widget _addAlignedWidget(Widget wdg){
    return Align(
      alignment: Alignment.centerLeft,
      child: 
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: wdg,
        ),
    );
  }

  Widget _addSeparator( {String spacing = "intermediate"} ){
    double height;
    switch(spacing){
      case "intermediate":
        height = 22.0;
      case "small":
        height = 8.0;
      case "large":
        height = 30.0;
      default:
        height = 25.0;
    }

    return SizedBox(height: height,);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        children: [
          _addAlignedWidget(
            // const Text("Immunophenotyping Workflow", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),)
            TextField(
              controller: workflowTfController,
              decoration: 
                const InputDecoration(
                  border: UnderlineInputBorder()
                ),
            )
          ),

          _addSeparator(),

          _addAlignedWidget(ElevatedButton(
              child: const Text("Select Team"),
              onPressed: ()  async {
                String team = ( await showPickerDialog(
                  context: context,
                  label: "",
                  items: teamNameList,
                ))!;

                setState(() {
                  selectedTeam = team;
                });
                // teamTfController.text = selectedTeam;
              }
            ),
          ),


          _addSeparator(spacing: "small"),
          

          _addAlignedWidget(Material( 
              child: 
              Text(
                selectedTeam, 
                style: 
                  const TextStyle(fontSize: 16, color: Colors.black)
              ),
            ) 
          ),
         

          _addSeparator(spacing: "intermediate"),

          _addAlignedWidget(const Text("Upload FCS Files.", style: TextStyle(fontSize: 16, color: Colors.black),)),

          _addSeparator(spacing: "small"),

          _addAlignedWidget(
            Table(
              columnWidths: const {
                0: FixedColumnWidth(30),
                1: IntrinsicColumnWidth()
              },
              children: [
                TableRow(
                  children: [
                    Material( 
                      child: InkWell(
                        onTap: () async {
                          result = (await FilePicker.platform.pickFiles())!;
                        },
                        child: const Icon(Icons.add_circle_outline_rounded),
                      )
                    ),
                    const Text("Choose Files", style: TextStyle(fontSize: 16, color: Colors.black),)
                  ]
                )
              ],
            )
          ),


          _addSeparator(spacing: "small"),


          _addAlignedWidget(
            Stack(
              children: [
                SizedBox(
                  height: 200,
                  width: 400,

                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey), borderRadius: BorderRadius.circular(2.0),color: dvBackground,),
                    child: ListView(
                      scrollDirection: Axis.vertical,
                      children: _buildFileList(),
                    ),
                  )
                ),

                SizedBox(
                  height: 200,
                  width: 400,
                  child: 
                    DropzoneView(
                      
                      operation: DragOperation.copy,
                      onCreated: (ctrl) => dvController = ctrl,
                      onLeave: () {
                        setState(() {
                          dvBackground = Colors.white;
                        });
                      },
                      onHover: () {
                        setState(() {
                          dvBackground = Colors.cyan.shade50;
                        });
                      },
                      onDrop:  (ev) async => _processSingleFileDrop(ev),
                      onDropMultiple: (dynamic ev) => (List<dynamic> ev) => print('Drop multiple: $ev'),
                    ),
                )
              ],
            )
          ),

          _addSeparator(spacing: "small"),

          _addAlignedWidget(
            ElevatedButton(

                onPressed: () {
                  finishedUploading = false;


                  progressDialog.show(msg: "Reading FCS files, please wait", barrierColor: const Color.fromARGB(125, 0, 0, 0));
                  
                  _uploadFiles();

                  Timer.periodic(const Duration(milliseconds: 250), (tmr){
                    if( finishedUploading == true){
                      tmr.cancel();
                      sub.cancel();
                      if( progressDialog.isOpen()){
                        progressDialog.close();
                      }
                      
                    }
                  });

                }, 
                child: const Text("Upload")
            )
          ),

        ],
      ),
    );
 
  }

}