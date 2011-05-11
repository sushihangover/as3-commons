package org.as3commons.codec.serialization.amf
{
	import flash.net.getClassByAlias;
	import flash.utils.ByteArray;
	import flash.utils.IDataInput;
	import flash.utils.IExternalizable;
	import flash.utils.getDefinitionByName;
	
	import org.as3commons.codec.serialization.utils.PropertyInfo;
	import org.as3commons.codec.serialization.utils.TraitsInfo;
	
	/**
	 * A port of the Adobe Java code in flex.messaging.io.amf.Amf3Input
	 * 
	 * @author Jan Van Coppenolle
	 */ 
	public class AMF3Input
	{
		private static const UTF_DATA_FORMAT_EXCEPTION:String = "UTF Data Format Exception";
		private static const OBJECT_NOT_IEXT_EXCEPTION:String = "Object is not IExternalizable";

		/**
		 * @private
		 */
		protected var input:IDataInput;
		
		/**
		 * @private
		 */
		protected var objectTable:Array;
	
		/**
		 * @private
		 */
		protected var stringTable:Vector.<String>;

		/**
		 * @private
		 */
		protected var traitsTable:Vector.<TraitsInfo>;
		
		/**
		 * Constructs a new AMF3 Deserializer.
		 * 
		 * @param input An IDataInput instance providing the bytes.
		 */
		public function AMF3Input(input:IDataInput = null)
		{
			if (input)
				load(input);
		}
		
		/**
		 * Loads the AMF3 bytes.
		 * 
		 * @param input An IDataInput instance providing the bytes.
		 */
		public function load(input:IDataInput):void
		{
			this.input = input;
			
			objectTable = [];
			stringTable = new Vector.<String>();
			traitsTable = new Vector.<TraitsInfo>();
		}
		
		/**
		 * Reads an object from the AMF3 bytes.
		 */
		public function readObject():*
		{
			var type:int = input.readByte();
			return readObjectValue(type);
		}
		
		/**
		 * Returns the traits table.
		 */
		public function getTraits():Vector.<TraitsInfo>
		{
			return traitsTable;
		}
		
		/**
		 * Nulls out all internally held references.
		 */
		public function dispose():void
		{
			input = null;
			
			objectTable = null;
			stringTable = null;
			traitsTable = null;
		}
		
		////////////////////////////////////////////////////////////////////////
		// Internal
		
		/**
		 * Reads an Object.
		 * @private
		 */
		protected function readObjectValue(type:int):*
		{
			switch (type)
			{
				case AMF3Type.UNDEFINED:
					return undefined;
				
				case AMF3Type.NULL:
					return null;
				
				case AMF3Type.FALSE:
					return false;
				
				case AMF3Type.TRUE:
					return true;
				
				case AMF3Type.INTEGER:
					return readUInt29();
				
				case AMF3Type.NUMBER:
					return readDouble();
				
				case AMF3Type.STRING:
					return readString();
				
				case AMF3Type.XML:
				case AMF3Type.XMLSTRING:
					return readXml();
				
				case AMF3Type.DATE:
					return readDate();
				
				case AMF3Type.ARRAY:
					return readArray();
				
				case AMF3Type.OBJECT:
					return readScriptObject();
				
				case AMF3Type.BYTEARRAY:
					return readByteArray();
				
				default:
					throw new Error("Unknown type: " + type.toString());
			}
		}
		
		/**
		 * Reads an integer.
		 * @private
		 */
		protected function readUInt29():int
		{
			var value:int = 0;
			var n:int = 0;
			var byte:uint = input.readUnsignedByte();
			
			while ((byte & 0x80) != 0 && n < 3)
			{
				value <<= 7;
				value |= (byte & 0x7F);
				byte = input.readUnsignedByte();
				++n;
			}
			
			if (n < 3)
			{
				value <<= 7;
				value |= byte;
			}
			else
			{
				value <<= 8;
				value |= byte;
				
				if ((value & 0x10000000) != 0)
					value |= 0xe0000000;
			}
			
			return value;
		}
		
		/**
		 * Reads a Number.
		 * @private
		 */
		protected function readDouble():Number
		{
			return input.readDouble();
		}
		
		/**
		 * Reads an Array.
		 * @private
		 */
		protected function readArray():Array
		{
			var ref:int = readUInt29();
			var name:String;
			var value:Object;
			var array:Array;
			var length:int;
			
			if ((ref & 0x01) == 0)
			{
				return getObjectReference(ref >> 1);
			}
			else
			{
				length = (ref >> 1);
				array = [];
				addObjectReference(array);
				
				while (true)
				{
					name = readString();
					
					if (name == null || name.length == 0)
						break;
					
					value = readObject();
					array[name] = value;
				}
				
				for (var i:int = 0; i < length; ++i)
				{
					value = readObject();
					array.push(value);
				}
				
				return array;
			}
		}
		
		/**
		 * Read Script Object
		 * @private
		 */
		protected function readScriptObject():Object
		{
			var ref:int = readUInt29();
			var object:Object;
			var traitsInfo:TraitsInfo;
			var propertyInfo:PropertyInfo;
			var property:String;
			var type:String;
			var kind:Class;
			var value:Object;
			
			if ((ref & 0x01) == 0)
			{
				return getObjectReference(ref >> 1);
			}
			else
			{
				traitsInfo = readTraits(ref);
				type = traitsInfo.type;
				
				try
				{
					if (type)
						kind = getClassByAlias(type) || Class(getDefinitionByName(type));
				}
				catch (e:Error)
				{
				}
				
				if (kind)
				{
					object = new kind();
					traitsInfo.kind = kind;
				}
				else
				{
					object = {};
				}
				
				addObjectReference(object);
				
				if (traitsInfo.isExternalizable)
				{
					readExternalizable(object);
				}
				else
				{
					for each (propertyInfo in traitsInfo.properties)
						object[propertyInfo.name] = readObject();
					
					if (traitsInfo.isDynamic)
					{
						while (true)
						{
							property = readString();
							
							if (property == null || property == "")
								break;
							
							object[property] = readObject();
						}
					}
				}
				
				return object;
			}
		}
		
		/**
		 * Use IExternizable impl to read out properties.
		 * @private
		 */
		protected function readExternalizable(object:Object):void
		{
			if (object is IExternalizable)
				IExternalizable(object).readExternal(input);
			else
				throw new Error(OBJECT_NOT_IEXT_EXCEPTION);
		}
		
		/**
		 * Reads a String.
		 * @private
		 */
		protected function readString():String
		{
			var ref:int = readUInt29();
			var str:String;
			var length:int;
			
			if ((ref & 0x01) == 0)
			{
				return getStringReference(ref >> 1);
			}
			else
			{
				length = (ref >> 1);
				
				if (0 == length)
					return "";
				
				str = readUTF(length);
				addStringReference(str);
				return str;
			}
		}
		
		/**
		 * Reads an UTF String.
		 * @private
		 */
		protected function readUTF(length:int):String
		{
			var string:String = "";
			var data:ByteArray = new ByteArray();
			var ch1:int;
			var ch2:int;
			var ch3:int;
			var count:int = 0;
			var ch:int = 0;
			
			input.readBytes(data, 0, length);
			
			while (count < length)
			{
				ch1 = data.readByte() & 0xFF;
				
				switch (ch1 >> 4)
				{
					case 0:
					case 1:
					case 2:
					case 3:
					case 4:
					case 5:
					case 6:
					case 7:
						count++;
						string += String.fromCharCode(ch1);
						break;
					case 12:
					case 13:
						count += 2;
						if (count > length)
							throw new Error(UTF_DATA_FORMAT_EXCEPTION);
						ch2 = data.readByte();
						if ((ch2 & 0xC0) != 0x80)
							throw new Error(UTF_DATA_FORMAT_EXCEPTION);
						string += String.fromCharCode(((ch1 & 0x1F) << 6) | (ch2 & 0x3F));
						break;
					case 14:
						count += 3;
						if (count > length)
							throw new Error(UTF_DATA_FORMAT_EXCEPTION);
						ch2 = data.readByte();
						ch3 = data.readByte();
						if (((ch2 & 0xC0) != 0x80) || ((ch3 & 0xC0) != 0x80))
							throw new Error(UTF_DATA_FORMAT_EXCEPTION);
						string += String.fromCharCode(((ch1 & 0x0F) << 12) | ((ch2 & 0x3F) << 6) | ((ch3 & 0x3F) << 0));
						break;
					default:
						throw new Error(UTF_DATA_FORMAT_EXCEPTION);
				}
				
				ch++;
			}
			
			return string;
		}
		
		/**
		 * Reads a Date object.
		 * @private
		 */
		protected function readDate():Date
		{
			var ref:int = readUInt29();
			var date:Date;
			
			if ((ref & 0x01) == 0)
			{
				return getObjectReference(ref >> 1);
			}
			else
			{
				date = new Date();
				date.setTime(input.readDouble());
				addObjectReference(date);
				return date;
			}
		}
		
		/**
		 * Reads a ByteArray object.
		 * @private
		 */
		protected function readByteArray():ByteArray
		{
			var ref:int = readUInt29();
			var data:ByteArray;
			var length:int;
			
			if ((ref & 0x01) == 0)
			{
				return getObjectReference(ref >> 1);
			}
			else
			{
				length = (ref >> 1);
				data = new ByteArray();
				addObjectReference(data);
				input.readBytes(data, 0, length);
				return data;
			}
		}
		
		/**
		 * Reads a string and creates a native XML object.
		 * @private
		 */
		protected function readXml():XML
		{
			var ref:int = readUInt29();
			var xml:String = "";
			var length:int;
			
			if ((ref & 0x01) == 0)
			{
				xml = getObjectReference(ref >> 1)
			}
			else
			{
				length = (ref >> 1);
				xml = readUTF(length);
				addObjectReference(xml);
			}
			
			return new XML(xml);
		}
		
		/**
		 * Read Traits.
		 * @private
		 */
		protected function readTraits(ref:int):TraitsInfo
		{
			var traitsInfo:TraitsInfo;
			var isExternalizable:Boolean;
			var isDynamic:Boolean;
			var propertyCount:int;
			var type:String;
			var index:int;
			var property:String;
			
			if ((ref & 0x03) == 1)
			{
				// This is a reference
				return getTraitsReference(ref >> 2);
			}
			else
			{
				type = readString();
				isExternalizable = ((ref & 0x04) == 4);
				isDynamic = ((ref & 0x08) == 8);
				
				traitsInfo = new TraitsInfo(type, isDynamic, isExternalizable);
				
				addTraitsReference(traitsInfo);

				propertyCount = (ref >> 4); /* uint29 */
				
				for (index = 0; index < propertyCount; ++index)
				{
					property = readString();
					traitsInfo.addProperty(property);
				}
				
				return traitsInfo;
			}
		}
		
		////////////////////////////////////////////////////////////////////////
		
		/**
		 * @private
		 */
		protected function getObjectReference(index:int):*
		{
			return objectTable[index];
		}
		
		/**
		 * @private
		 */
		protected function addObjectReference(value:*):void
		{
			objectTable.push(value);
		}
		
		/**
		 * @private
		 */
		protected function getStringReference(index:int):*
		{
			return stringTable[index];
		}
		
		/**
		 * @private
		 */
		protected function addStringReference(value:String):void
		{
			stringTable.push(value);
		}
		
		/**
		 * @private
		 */
		protected function getTraitsReference(index:int):TraitsInfo
		{
			return traitsTable[index];
		}
		
		/**
		 * @private
		 */
		protected function addTraitsReference(value:TraitsInfo):void
		{
			traitsTable.push(value);
		}
	}
}