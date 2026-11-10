import {ApiError} from './errors';

// Official GST/e-Way Bill jurisdiction codes:
// https://docs.ewaybillgst.gov.in/apidocs/state-code.html
const GST_STATE:Readonly<Record<string,string>>={
 JK:'01',HP:'02',PB:'03',CH:'04',UK:'05',UT:'05',HR:'06',DL:'07',RJ:'08',
 UP:'09',BR:'10',SK:'11',AR:'12',NL:'13',MN:'14',MZ:'15',TR:'16',ML:'17',
 AS:'18',WB:'19',JH:'20',OD:'21',CG:'22',CT:'22',MP:'23',GJ:'24',
 DN:'26',DD:'26',DH:'26',MH:'27',KA:'29',GA:'30',LD:'31',KL:'32',TN:'33',
 PY:'34',AN:'35',TG:'36',TS:'36',AP:'37',LA:'38'
};
const UNION_WITHOUT_LEGISLATURE=new Set(['AN','CH','DN','DD','DH','LD','LA']);
export interface GstSplit {cgstPaise:bigint;sgstPaise:bigint;utgstPaise:bigint;igstPaise:bigint;cessPaise:bigint}
export function splitOrderGst(taxPaise:bigint,registered:{
 gstin:string|null;gstRegistration:string;verifiedAt:Date|null
},destinationStateCode:string):GstSplit {
 if(taxPaise<0n)throw new ApiError(422,'INVALID_TAX','Tax must not be negative.');
 const empty={cgstPaise:0n,sgstPaise:0n,utgstPaise:0n,igstPaise:0n,cessPaise:0n};
 if(taxPaise===0n)return empty;
 const jurisdiction=GST_STATE[destinationStateCode.toUpperCase()];
 if(!jurisdiction)throw new ApiError(422,'GST_JURISDICTION_UNKNOWN',
  'Cannot determine GST jurisdiction for the destination state.');
 if(registered.gstRegistration!=='REGULAR'||!registered.gstin||!registered.verifiedAt||
   !/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9]$/.test(registered.gstin))
  throw new ApiError(422,'GST_SUPPLIER_UNVERIFIED',
   'Taxable products require an approved supplier GST registration.');
 if(registered.gstin.slice(0,2)!==jurisdiction)
  return {...empty,igstPaise:taxPaise};
 const central=taxPaise/2n;
 const local=taxPaise-central;
 if(UNION_WITHOUT_LEGISLATURE.has(destinationStateCode.toUpperCase()))
  return {...empty,cgstPaise:central,utgstPaise:local};
 return {...empty,cgstPaise:central,sgstPaise:local};
}
