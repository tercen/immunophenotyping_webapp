import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:immunophenotyping_template_assistant/annotation_screen.dart';
import 'package:immunophenotyping_template_assistant/fcs_load_screen.dart';


//TODO list
// 1: Use InkWell on left panel to navigate screens on the right
// *: Use MediaQuery to scale text across the application

void main() => runApp(const ImmunophenotypingApp());

class ImmunophenotypingApp extends StatelessWidget {
  const ImmunophenotypingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: TwoColumnHome(),
    );
  }
}


class TwoColumnHome extends StatefulWidget {
  const TwoColumnHome({super.key});

  @override
  State<TwoColumnHome> createState()=> _TwoColumnHomeState();

}

class _TwoColumnHomeState extends State<TwoColumnHome>{
  final Widget _verticalDivider = Expanded(child: Container(constraints: const BoxConstraints(maxHeight: 1000, maxWidth: 5, minHeight: 50), color: Colors.black,) );
  // static const Widget _fcsLoadScreen = FcsLoadScreen();
  // static const Widget _annotationScreen = FcsLoadScreen();
  
  static Widget _addItem( IconData icon, String label, Widget screenTo){
    var inset = const EdgeInsets.symmetric(vertical: 5, horizontal: 5);
    var tbl = Align(
      alignment: Alignment.centerLeft,
      child: Table(
      columnWidths: const {
        0: FixedColumnWidth(32),
        1: IntrinsicColumnWidth()
      },


      children: [
        TableRow(
          children: [
            Padding(padding: inset, child:Icon(icon)),
            Padding(padding: inset, child:Text(label, style: const TextStyle(color: Colors.black, fontSize: 18),),),
          ]

        )
        
      ],
    ),
    );
    return tbl;
  }

  final Widget _buildLeftTab = ListView(
    scrollDirection: Axis.vertical,
    shrinkWrap: true,
    children: [
      Text("Test")
      // _addItem(Icons.home_rounded, "FCS Files", const FcsLoadScreen()),
      // _addItem(Icons.search_rounded, "Annotations", const AnnotationScreen()),
      // _addItem(Icons.settings, "Settings"),
    ],
  );

  Widget _buildRightScreen(){
    return const FcsLoadScreen();
  }


  @override
  Widget build(BuildContext context) {
    var wdg = Container(
      alignment: Alignment.topLeft,
      child: 
      Table(
        columnWidths: 
          const {
            0: FixedColumnWidth(250.0),
            1: FixedColumnWidth(5.0),
            2: IntrinsicColumnWidth(),
          },
        children: [
          TableRow(
            children: [
              _buildLeftTab,
              _verticalDivider,
              _buildRightScreen(),
            ]
          )
        ],
      ),
    );


    return Material(
      child: Column(children: [Text("Test")],),
    );
  }


}