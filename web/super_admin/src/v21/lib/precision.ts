/** Paise and Decimal values remain strings; no floating-point money calculations. */
const integer=/^-?(?:0|[1-9][0-9]*)$/;
const decimal=/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/;

export function formatPaise(amount:string):string {
 if(!integer.test(amount))throw new Error('Invalid exact paise amount');
 const value=BigInt(amount);
 const abs=value<0n?-value:value;
 const rupees=abs/100n;
 const fraction=(abs%100n).toString().padStart(2,'0');
 const grouping=new Intl.NumberFormat('en-IN',{maximumFractionDigits:0}).format(rupees);
 return (value<0n?'-':'')+'₹'+grouping+'.'+fraction;
}
export function formatDecimalQuantity(value:string,unit?:string):string {
 if(!decimal.test(value))throw new Error('Invalid exact quantity');
 if(unit!==undefined&&!/^[A-Za-z0-9/_ .-]{1,24}$/.test(unit))throw new Error('Invalid unit label');
 return value+(unit?' '+unit:'');
}
export function withExpectedVersion<T extends Record<string,unknown>>(body:T,version:number):T&{expectedVersion:number}{
 if(!Number.isSafeInteger(version)||version<0)throw new Error('Invalid optimistic version');
 return {...body,expectedVersion:version};
}
